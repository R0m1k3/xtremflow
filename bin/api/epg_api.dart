import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist_config.dart';
import '../services/xmltv_epg_service.dart';
import '../utils/log_redactor.dart';

/// API EPG — proxy vers Xtream avec cache 30 minutes
/// GET /api/epg/<channel_id>?days=1
///
/// Le panneau de l'abonné reste la source de référence, mais par son dump
/// `xmltv.php` d'abord : une requête couvre toutes les chaînes, là où
/// `player_api` en réclame une par chaîne à plusieurs secondes pièce. Vient
/// ensuite l'interrogation chaîne par chaîne, puis une source XMLTV externe
/// en dernier recours — cas des revendeurs dont le guide est figé depuis
/// plusieurs jours.
class EpgApi {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;

  /// Repli XMLTV. `null` quand aucune source n'est configurée : l'API se
  /// comporte alors exactement comme avant, sans le moindre appel sortant.
  final XmltvEpgService? _xmltv;

  /// Cache mémoire : « dns|username|channelId » → {data, expiresAt}.
  ///
  /// La clé inclut le compte : les `stream_id` sont propres à chaque panneau,
  /// deux playlists distinctes peuvent parfaitement partager le même
  /// identifiant et se servaient alors le guide l'une de l'autre.
  final Map<String, _CacheEntry> _cache = {};

  /// Correspondance `stream_id` → identifiant EPG et nom, par compte.
  /// Nécessaire au repli : le dump XMLTV indexe par identifiant de chaîne,
  /// pas par `stream_id` propre au panneau.
  final Map<String, _ChannelMap> _channelMaps = {};

  /// Client HTTP des appels `player_api`. Injectable pour les tests.
  final http.Client _http;

  /// Fabrique de la source XMLTV du panneau, une par compte.
  final XmltvEpgService Function(PlaylistConfig) _panelXmltvBuilder;

  /// Index XMLTV du panneau, par compte.
  final Map<String, XmltvEpgService> _panelXmltv = {};

  EpgApi(
    this._getPlaylist, {
    XmltvEpgService? xmltv,
    http.Client? httpClient,
    XmltvEpgService Function(PlaylistConfig)? panelXmltvBuilder,
  })  : _xmltv = xmltv,
        _http = httpClient ?? http.Client(),
        _panelXmltvBuilder = panelXmltvBuilder ?? _defaultPanelXmltv;

  /// Dump XMLTV servi par le panneau lui-même.
  ///
  /// POURQUOI : `player_api.php?action=get_simple_data_table` répond en
  /// plusieurs secondes chez beaucoup de revendeurs, et il faut un appel par
  /// chaîne — afficher une grille de trente chaînes demandait donc plus d'une
  /// minute. `xmltv.php` renvoie le guide de toutes les chaînes en une seule
  /// requête, réutilisée ensuite pendant des heures. C'est ce que font les
  /// clients IPTV rapides.
  static XmltvEpgService _defaultPanelXmltv(PlaylistConfig playlist) {
    final user = Uri.encodeQueryComponent(playlist.username);
    final password = Uri.encodeQueryComponent(playlist.password);
    return XmltvEpgService(
      sourceUrls: ['${playlist.dns}/xmltv.php?username=$user&password=$password'],
      refreshInterval: const Duration(hours: 3),
      // Le guide est facultatif : on ne fait pas patienter l'utilisateur
      // plusieurs minutes sur un panneau qui traîne.
      downloadTimeout: const Duration(seconds: 90),
    );
  }

  Future<Response> handleGetEpg(Request request, String channelId) async {
    final playlist = await _getPlaylist(request);
    if (playlist == null) {
      return Response.forbidden(
        json.encode({'error': 'Playlist non trouvée'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final cacheKey = '${playlist.dns}|${playlist.username}|$channelId';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return Response.ok(
        cached.data,
        headers: {'Content-Type': 'application/json', 'X-Cache': 'HIT'},
      );
    }

    try {
      // Sources par ordre de préférence. On s'arrête à la première qui
      // contient un programme en cours ou à venir ; à défaut, la première
      // non vide sert de repli.
      //
      // Le dump du panneau passe devant : une requête couvre toutes les
      // chaînes, là où `player_api` en demande une par chaîne, à plusieurs
      // secondes pièce.
      final sources = <(String, Future<List<Map<String, dynamic>>> Function())>[
        ('panel-xmltv', () => _panelProgrammes(playlist, channelId)),
        ('xtream', () => _xtreamProgrammes(playlist, channelId)),
        ('xmltv', () => _xmltvProgrammes(playlist, channelId)),
      ];

      var epgData = <String, dynamic>{
        'channel_id': channelId,
        'programmes': <Map<String, dynamic>>[],
      };
      var source = 'xtream';
      var found = false;

      for (final (name, fetch) in sources) {
        final programmes = await fetch();
        if (programmes.isEmpty) continue;

        final candidate = <String, dynamic>{
          'channel_id': channelId,
          'programmes': programmes,
        };
        if (!found) {
          // Meilleur repli connu à ce stade, même si le guide est périmé.
          epgData = candidate;
          source = name;
          found = true;
        }
        if (_hasCurrentProgramme(candidate)) {
          epgData = candidate;
          source = name;
          break;
        }
      }

      final jsonStr = json.encode(epgData);

      // Mettre en cache 30 minutes
      _cache[cacheKey] = _CacheEntry(
        data: jsonStr,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );

      return Response.ok(
        jsonStr,
        headers: {
          'Content-Type': 'application/json',
          'X-Cache': 'MISS',
          'X-Epg-Source': source,
        },
      );
    } catch (e) {
      // Détail redacté en log uniquement : une ClientException Dart contient
      // l'URI amont, credentials Xtream inclus.
      print('[EpgApi] Erreur EPG: ${LogRedactor.redactUrl('$e')}');
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur lors de la récupération EPG'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Programmes tirés du dump XMLTV du panneau, ou liste vide.
  Future<List<Map<String, dynamic>>> _panelProgrammes(
    PlaylistConfig playlist,
    String channelId,
  ) async {
    final key = '${playlist.dns}|${playlist.username}';
    final service =
        _panelXmltv.putIfAbsent(key, () => _panelXmltvBuilder(playlist));
    return _fromXmltv(service, playlist, channelId);
  }

  /// Programmes obtenus en interrogeant le panneau chaîne par chaîne.
  ///
  /// Chemin lent : deux actions possibles, plusieurs secondes chacune chez la
  /// plupart des revendeurs. Il ne sert que lorsque le dump XMLTV du panneau
  /// est absent ou ne couvre pas la chaîne.
  Future<List<Map<String, dynamic>>> _xtreamProgrammes(
    PlaylistConfig playlist,
    String channelId,
  ) async {
    // `get_simple_data_table` d'abord : c'est la seule action réellement
    // universelle. `get_epg` n'existe pas sur beaucoup de panneaux — au lieu
    // d'une erreur, ils renvoient poliment le payload d'authentification,
    // sans champ `epg_listings`, ce qui produisait un guide vide impossible
    // à distinguer d'une chaîne sans programme.
    const actions = ['get_simple_data_table', 'get_short_epg'];

    for (final action in actions) {
      final url =
          '${playlist.dns}/player_api.php?username=${playlist.username}'
          '&password=${playlist.password}'
          '&action=$action&stream_id=$channelId';

      final response =
          await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) continue;

      Map<String, dynamic> parsed;
      try {
        parsed = transformEpgData(json.decode(response.body), channelId);
      } catch (_) {
        continue;
      }
      final programmes = (parsed['programmes'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (programmes.isNotEmpty) return programmes;
    }
    return const [];
  }

  /// Le guide contient-il un programme en cours ou à venir ?
  ///
  /// Un panneau dont l'EPG est figé répond avec des centaines de programmes,
  /// tous terminés depuis plusieurs jours. Compter les entrées ne suffit donc
  /// pas à décider si le guide est exploitable.
  static bool _hasCurrentProgramme(Map<String, dynamic> epgData) {
    final now = DateTime.now().toUtc();
    for (final programme in epgData['programmes'] as List) {
      if (programme is! Map) continue;
      final end = DateTime.tryParse('${programme['end']}');
      if (end != null && end.isAfter(now)) return true;
    }
    return false;
  }

  /// Programmes issus du dump XMLTV, ou liste vide si indisponible.
  Future<List<Map<String, dynamic>>> _xmltvProgrammes(
    PlaylistConfig playlist,
    String channelId,
  ) =>
      _fromXmltv(_xmltv, playlist, channelId);

  /// Programmes d'une chaîne dans un index XMLTV quelconque (panneau ou
  /// source externe), ou liste vide si l'index ne la connaît pas.
  Future<List<Map<String, dynamic>>> _fromXmltv(
    XmltvEpgService? xmltv,
    PlaylistConfig playlist,
    String channelId,
  ) async {
    if (xmltv == null) return const [];

    try {
      final channels = await _channelMapFor(playlist);
      final epgId = channels.epgIds[channelId];
      final name = channels.names[channelId];
      if (epgId == null && name == null) return const [];

      final programmes =
          await xmltv.programmesFor(epgId, displayName: name);
      if (programmes.isEmpty) return const [];

      final now = DateTime.now().toUtc();
      return programmes
          .where((p) => p.stop.isAfter(now))
          .take(64)
          .map((p) => p.toJson(channelId))
          .toList();
    } catch (e) {
      print('[EpgApi] source XMLTV indisponible pour $channelId : $e');
      return const [];
    }
  }

  /// Table des chaînes du compte, rafraîchie toutes les 6 heures.
  Future<_ChannelMap> _channelMapFor(PlaylistConfig playlist) async {
    final key = '${playlist.dns}|${playlist.username}';
    final cached = _channelMaps[key];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached;
    }

    final url = '${playlist.dns}/player_api.php'
        '?username=${playlist.username}&password=${playlist.password}'
        '&action=get_live_streams';
    final response =
        await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));

    final epgIds = <String, String>{};
    final names = <String, String>{};
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final streamId = item['stream_id']?.toString();
          if (streamId == null || streamId.isEmpty) continue;
          final epgId = item['epg_channel_id']?.toString();
          if (epgId != null && epgId.isNotEmpty) epgIds[streamId] = epgId;
          final name = item['name']?.toString();
          if (name != null && name.isNotEmpty) names[streamId] = name;
        }
      }
    }

    final map = _ChannelMap(
      epgIds: epgIds,
      names: names,
      expiresAt: DateTime.now().add(const Duration(hours: 6)),
    );
    _channelMaps[key] = map;
    return map;
  }

  /// Normalise une réponse Xtream (`epg_listings`) vers le format servi au
  /// client. Public pour être couvert par `bin/test/epg_api_test.dart`.
  Map<String, dynamic> transformEpgData(dynamic raw, String channelId) {
    try {
      List<dynamic> listings = [];

      if (raw is Map && raw.containsKey('epg_listings')) {
        listings = raw['epg_listings'] as List<dynamic>? ?? [];
      } else if (raw is List) {
        listings = raw;
      }

      final programmes = listings.map((item) {
        // Les champs texte `start`/`end` sont exprimés dans le fuseau du
        // panneau (souvent Europe/Amsterdam), sans indicateur de zone : le
        // client les relisait comme de l'heure locale et décalait tout le
        // guide. Les `*_timestamp` sont de l'epoch UTC — on s'en sert dès
        // qu'ils sont présents et on émet de l'ISO-8601 UTC explicite.
        final start = _isoUtc(item['start_timestamp']) ??
            _normalizeDate(item['start'] as String? ?? '');
        final end = _isoUtc(item['stop_timestamp']) ??
            _isoUtc(item['end_timestamp']) ??
            _normalizeDate(
              (item['stop'] as String?) ?? (item['end'] as String?) ?? '',
            );

        // Décoder le titre (base64 si nécessaire)
        String title = item['title'] as String? ?? '';
        try {
          if (title.isNotEmpty) {
            final decoded = utf8.decode(base64Decode(title));
            if (decoded.isNotEmpty) title = decoded;
          }
        } catch (_) {}

        String description = item['description'] as String? ?? '';
        try {
          if (description.isNotEmpty) {
            final decoded = utf8.decode(base64Decode(description));
            if (decoded.isNotEmpty) description = decoded;
          }
        } catch (_) {}

        return {
          'title': title,
          'description': description,
          'start': start,
          'end': end,
          'channel_id': channelId,
        };
      }).toList();

      return {'channel_id': channelId, 'programmes': programmes};
    } catch (e) {
      print('[EpgApi] Erreur panneau pour $channelId: ${LogRedactor.redactUrl('$e')}');
      return {
        'channel_id': channelId,
        'programmes': [],
        'error': 'EPG indisponible',
      };
    }
  }

  /// Epoch (secondes, String ou int) → ISO-8601 UTC, ou `null` si absent.
  static String? _isoUtc(dynamic timestamp) {
    if (timestamp == null) return null;
    final seconds = timestamp is int ? timestamp : int.tryParse('$timestamp');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toIso8601String();
  }

  /// Repli : « YYYY-MM-DD HH:MM:SS » → « YYYY-MM-DDTHH:MM:SS ».
  static String _normalizeDate(String raw) {
    if (raw.contains(' ') && !raw.contains('T')) {
      return raw.replaceFirst(' ', 'T');
    }
    return raw;
  }
}

class _ChannelMap {
  final Map<String, String> epgIds;
  final Map<String, String> names;
  final DateTime expiresAt;
  _ChannelMap({
    required this.epgIds,
    required this.names,
    required this.expiresAt,
  });
}

class _CacheEntry {
  final String data;
  final DateTime expiresAt;
  _CacheEntry({required this.data, required this.expiresAt});
}
