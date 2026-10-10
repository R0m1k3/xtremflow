import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playlist_config.dart';

/// Connexions ouvertes vers le fournisseur Xtream, par compte.
///
/// POURQUOI : la plupart des abonnements n'autorisent qu'UNE connexion
/// simultanée (`max_connections: "1"`, vérifié en prod). Or un FFmpeg de
/// lecture survit au spectateur : 4 min pour un direct HLS, jusqu'à 15 min
/// ou la fin du téléchargement pour un film, le temps de détecter la
/// déconnexion pour `turbo.ts`. Le flux suivant tombait sur un slot occupé :
/// le panneau répondait `HTTP 551` ou ne répondait pas (timeout), d'où les
/// films « indisponibles » et les zaps qui échouent.
///
/// Règle : avant d'ouvrir une nouvelle connexion amont, on coupe les
/// connexions ORPHELINES du même compte (plus personne ne les consomme),
/// les plus anciennes d'abord, jusqu'à lui faire de la place.
///
/// Un flux encore regardé n'est jamais coupé. Une première version coupait
/// sans distinction (« le dernier gagne ») : deux lecteurs ouverts sur un
/// compte à une connexion se coupaient alors en boucle, chacun relançant
/// aussitôt — plus aucune image nulle part (constaté en prod). Le second
/// lecteur est désormais refusé par le panneau, comme avant, et le premier
/// continue.
///
/// Les enregistrements n'y sont pas inscrits : ils ne sont jamais coupés.
class UpstreamSlots {
  final DateTime Function() _now;
  final Map<String, _Slot> _slots = {};
  int _nextToken = 0;

  UpstreamSlots({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Inscrit la connexion [id] du compte [account]. [release] la coupe.
  ///
  /// Renvoie un jeton à repasser à [unregister] : une session relancée sous
  /// le même identifiant ne doit pas être désinscrite par la fin de
  /// l'ancien processus.
  ///
  /// [isActive] : vrai tant qu'un spectateur consomme le flux. Une
  /// connexion active n'est jamais coupée par [makeRoom].
  int register({
    required String id,
    required String account,
    required void Function() release,
    bool Function()? isActive,
  }) {
    final token = ++_nextToken;
    _slots[id] = _Slot(token, account, _now(), release, isActive);
    return token;
  }

  void unregister(String id, {int? token}) {
    final slot = _slots[id];
    if (slot == null) return;
    if (token != null && slot.token != token) return;
    _slots.remove(id);
  }

  int countFor(String account) =>
      _slots.values.where((s) => s.account == account).length;

  /// Libère assez de connexions de [account] pour qu'une nouvelle tienne
  /// sous [max]. [keep] (la session demandée) n'est jamais coupée.
  ///
  /// [max] <= 0 = quota inconnu : on ne coupe rien plutôt que de risquer
  /// d'interrompre un autre spectateur.
  List<String> makeRoom(String account, {required int max, required String keep}) {
    if (max <= 0) return const [];
    final others = _slots.entries
        .where((e) => e.value.account == account && e.key != keep)
        .toList();

    final excess = others.length - (max - 1);
    if (excess <= 0) return const [];

    final orphans = others.where((e) => !e.value.active).toList()
      ..sort((a, b) => a.value.since.compareTo(b.value.since));

    final freed = <String>[];
    for (final entry in orphans.take(excess)) {
      _slots.remove(entry.key);
      try {
        entry.value.release();
      } catch (_) {}
      freed.add(entry.key);
    }
    return freed;
  }
}

class _Slot {
  final int token;
  final String account;
  final DateTime since;
  final void Function() release;
  final bool Function()? isActive;
  _Slot(this.token, this.account, this.since, this.release, this.isActive);

  bool get active {
    try {
      return isActive?.call() ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Clé de compte : deux playlists sur les mêmes identifiants partagent le
/// même quota chez le fournisseur.
String accountKeyOf(PlaylistConfig p) => '${p.dns}|${p.username}';

/// `user_info.max_connections` d'une réponse `player_api.php`, ou null.
int? parseMaxConnections(Object? json) {
  if (json is! Map) return null;
  final info = json['user_info'];
  if (info is! Map) return null;
  final raw = info['max_connections'];
  final value = raw is int ? raw : int.tryParse('$raw');
  return (value != null && value > 0) ? value : null;
}

/// Quota de connexions par compte, lu chez le fournisseur et mis en cache.
///
/// Ne fait JAMAIS attendre un flux : `player_api.php` met jusqu'à 4 s à
/// répondre (mesuré en prod), délai qui s'ajoutait au démarrage du premier
/// flux puis de chaque flux suivant l'expiration du cache. La valeur connue
/// (même périmée), sinon [fallback], est rendue immédiatement ; la lecture
/// chez le panneau se fait en arrière-plan. Sans risque : le quota ne sert
/// qu'à décider quels flux ORPHELINS couper.
class AccountLimits {
  final Duration ttl;
  final Future<int?> Function(PlaylistConfig) _fetch;
  final Map<String, ({int max, DateTime at})> _cache = {};
  final Set<String> _refreshing = {};

  /// Valeur retenue tant que le panneau n'a pas répondu : un seul flux, le
  /// cas de loin le plus courant chez les fournisseurs Xtream.
  static const fallback = 1;

  AccountLimits({
    this.ttl = const Duration(minutes: 10),
    Future<int?> Function(PlaylistConfig)? fetch,
  }) : _fetch = fetch ?? _fetchFromPanel;

  Future<int> maxFor(PlaylistConfig p) async {
    final key = accountKeyOf(p);
    final cached = _cache[key];
    if (cached == null || DateTime.now().difference(cached.at) >= ttl) {
      _refresh(key, p);
    }
    return cached?.max ?? fallback;
  }

  void _refresh(String key, PlaylistConfig p) {
    if (!_refreshing.add(key)) return; // une seule lecture à la fois
    Future<int?>.sync(() => _fetch(p))
        .then<int?>((v) => v, onError: (Object _) => null)
        .then((value) {
      // Un échec n'est pas mis en cache : on réessaiera au prochain flux.
      if (value != null) _cache[key] = (max: value, at: DateTime.now());
    }).whenComplete(() => _refreshing.remove(key));
  }

  static Future<int?> _fetchFromPanel(PlaylistConfig p) async {
    final uri = Uri.parse('${p.dns}/player_api.php').replace(
      queryParameters: {'username': p.username, 'password': p.password},
    );
    final client = http.Client();
    try {
      final response = await client.get(uri, headers: {
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      return parseMaxConnections(jsonDecode(response.body));
    } finally {
      client.close();
    }
  }
}
