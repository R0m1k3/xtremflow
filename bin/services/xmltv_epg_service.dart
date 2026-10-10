import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

import '../utils/log_redactor.dart';

/// Guide TV construit à partir de dumps XMLTV publics.
///
/// Beaucoup de panneaux Xtream servent un EPG figé depuis plusieurs jours, ou
/// n'en servent aucun : `get_simple_data_table` répond alors correctement mais
/// avec des programmes périmés. Ce service télécharge des dumps XMLTV
/// indépendants, les indexe par chaîne, et permet de compléter le guide.
///
/// Le parsing est fait en flux (`XmlEventReader`) : un dump national pèse
/// couramment 50 Mo décompressés, en charger l'arbre DOM complet coûterait
/// plusieurs centaines de mégaoctets dans le conteneur.
class XmltvEpgService {
  XmltvEpgService({
    required this.sourceUrls,
    this.refreshInterval = const Duration(hours: 6),
    this.retention = const Duration(hours: 6),
    this.horizon = const Duration(hours: 48),
    this.retryBackoff = const Duration(minutes: 15),
    this.downloadTimeout = const Duration(minutes: 5),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Dumps XMLTV à agréger, dans l'ordre de priorité décroissante.
  final List<String> sourceUrls;

  /// Fréquence de rafraîchissement de l'index.
  final Duration refreshInterval;

  /// Les programmes terminés depuis plus longtemps que cette durée sont
  /// écartés à l'indexation : personne ne consulte le guide d'hier, et les
  /// garder double la taille de l'index.
  final Duration retention;

  /// Les programmes qui commencent au-delà de cet horizon sont écartés à
  /// l'indexation.
  ///
  /// Un dump national couvre souvent sept jours pour un millier de chaînes ;
  /// tout garder en mémoire dans le conteneur coûte des centaines de
  /// mégaoctets pour un guide qui n'affiche que le programme courant et les
  /// suivants.
  final Duration horizon;

  /// Délai minimal entre deux tentatives quand aucune source n'a répondu.
  ///
  /// Sans ce recul, une source morte était retéléchargée à chaque consultation
  /// du guide — une requête sortante par chaîne affichée, soit exactement le
  /// flot qu'un index est censé éviter.
  final Duration retryBackoff;

  /// Plafond de téléchargement d'un dump. Le guide est facultatif : mieux vaut
  /// abandonner et servir le panneau que faire attendre l'utilisateur.
  final Duration downloadTimeout;

  final http.Client _client;

  /// clé de chaîne normalisée → programmes triés par heure de début.
  Map<String, List<XmltvProgramme>> _index = {};
  DateTime? _indexedAt;
  DateTime? _failedAt;
  Future<void>? _refreshInFlight;

  bool get hasData => _index.isNotEmpty;
  DateTime? get indexedAt => _indexedAt;
  int get channelCount => _index.length;

  /// Programmes d'une chaîne, ou liste vide si inconnue.
  ///
  /// [channelId] est l'`epg_channel_id` renvoyé par Xtream ; [displayName] est
  /// le nom de la chaîne, utilisé en second recours car les dumps publics
  /// construisent souvent leur identifiant à partir du nom affiché.
  Future<List<XmltvProgramme>> programmesFor(
    String? channelId, {
    String? displayName,
  }) async {
    await ensureFresh();
    final direct = _lookup(channelId, displayName);
    if (direct.isNotEmpty) return direct;

    // Chaîne décalée sans guide propre (« TF1 +1 » absent des dumps) : le
    // guide de la chaîne principale, une heure plus tard, est exact.
    if (displayName != null && _plusOne.hasMatch(displayName)) {
      final base = displayName.replaceAll(_plusOne, ' ');
      final hits = _lookup(null, base);
      return [
        for (final p in hits)
          XmltvProgramme(
            title: p.title,
            description: p.description,
            start: p.start.add(const Duration(hours: 1)),
            stop: p.stop.add(const Duration(hours: 1)),
          ),
      ];
    }
    return const [];
  }

  static final _plusOne = RegExp(r'\+\s*1(?![0-9])');

  List<XmltvProgramme> _lookup(String? channelId, String? displayName) {
    final keys = [
      normalizeKey(channelId),
      if (displayName != null) ...nameKeys(displayName),
      // Clés souples en dernier recours, dans leur propre espace de noms.
      _looseIndexKey(looseKey(channelId)),
      if (displayName != null)
        _looseIndexKey(looseKey(cleanChannelName(displayName).name)),
    ];
    for (final key in keys) {
      if (key.isEmpty) continue;
      final hit = _index[key];
      if (hit != null && hit.isNotEmpty) return hit;
    }
    return const [];
  }

  static String _looseIndexKey(String loose) => loose.isEmpty ? '' : '~$loose';

  /// Jetons sans valeur distinctive pour reconnaître une chaîne.
  static const _looseNoise = {
    'channel', 'tv', 'hd', 'fhd', 'uhd', 'sd', '4k', 'hevc',
  };

  /// Codes pays en fin d'identifiant XMLTV (`TF1.fr`, `RTS1.ch`).
  static const _countryCodes = {
    'fr', 'be', 'ch', 'lu', 'mc', 'ca', 'uk', 'us', 'es', 'it', 'de', 'pt',
    'nl',
  };

  /// Clé « souple » : sans code pays final ni mots génériques
  /// (« AB3.Channel.fr » et « AB3 » → `ab3`).
  ///
  /// Servie dans un espace de noms à part, consultée en tout dernier : elle
  /// rattrape les variantes d'écriture sans fausser les correspondances
  /// exactes.
  static String looseKey(String? raw) {
    if (raw == null) return '';
    final folded = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      folded.write(_accents[char] ?? char);
    }
    final tokens = folded
        .toString()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length > 1 && _countryCodes.contains(tokens.last)) {
      tokens.removeLast();
    }
    tokens.removeWhere(_looseNoise.contains);
    return tokens.join();
  }

  /// Préfixe pays des noms de panneau : `FR - `, `FR: `, `|FR| `, `[FR] `…
  static final _countryPrefix = RegExp(
    r'^\s*[\|\[\(]?\s*([A-Za-z]{2,3})\s*[\|\]\)]?\s*[-:|]\s*|^\s*[\|\[\(]\s*([A-Za-z]{2,3})\s*[\|\]\)]\s*',
  );

  /// Marqueurs de qualité ou de source en fin de nom, sans rapport avec la
  /// chaîne elle-même.
  static final _qualitySuffix = RegExp(
    r'(\s+|^)(fhd|uhd|hd|sd|hq|lq|4k|8k|hevc|h\.?265|h\.?264|1080p?|720p?|'
    r'50fps|60fps|backup|raw|vip|multi|\(backup\)|\(multi\))\s*$',
    caseSensitive: false,
  );

  /// Clés candidates pour retrouver une chaîne du panneau par son nom.
  ///
  /// POURQUOI : en prod, 59 % des chaînes françaises n'ont pas
  /// d'`epg_channel_id`. Leur nom brut (« FR - TF1 FHD ◉ » → `frtf1fhd`) ne
  /// correspond à aucune entrée XMLTV (`TF1.fr`, « TF1 »). On retire le
  /// préfixe pays, les marqueurs de qualité et les symboles, puis on tente
  /// aussi la forme `nom.pays` qu'utilisent les dumps publics.
  ///
  /// Le décalage horaire (« +1 ») est conservé : TF1 +1 n'a pas le guide
  /// de TF1.
  static List<String> nameKeys(String name) {
    final keys = <String>[normalizeKey(name)];
    final cleaned = cleanChannelName(name);
    final country = cleaned.country;
    final base = normalizeKey(cleaned.name);
    if (base.isNotEmpty) {
      keys.add(base);
      keys.add('$base${country ?? 'fr'}');
    }
    return keys.where((k) => k.isNotEmpty).toSet().toList();
  }

  /// Abréviations du panneau pour les chaînes publiques (« F3 ALPES »), là
  /// où les dumps écrivent `France.3.-.Alpes.fr`.
  static final _franceAbbrev = RegExp(r'^F\s?([2-5])\b', caseSensitive: false);

  /// Nom de chaîne débarrassé du préfixe pays, des symboles et des
  /// marqueurs de qualité ; [country] = code pays du préfixe, s'il y en a.
  static ({String name, String? country}) cleanChannelName(String raw) {
    var cleaned = raw;
    String? country;
    final prefix = _countryPrefix.firstMatch(cleaned);
    if (prefix != null) {
      country = (prefix.group(1) ?? prefix.group(2))?.toLowerCase();
      cleaned = cleaned.substring(prefix.end);
    }
    // Symboles décoratifs (◉, ᴴᴰ, ★…) : tout ce qui n'est ni lettre, ni
    // chiffre, ni ponctuation utile.
    cleaned = cleaned
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s+.&\-()]', unicode: true), ' ')
        .trim();
    String previous;
    do {
      previous = cleaned;
      cleaned = cleaned.replaceFirst(_qualitySuffix, '').trim();
    } while (cleaned != previous && cleaned.isNotEmpty);
    cleaned = cleaned.replaceFirstMapped(
      _franceAbbrev,
      (m) => 'France ${m[1]}',
    );
    return (name: cleaned, country: country);
  }

  /// Recharge l'index s'il est absent ou périmé. Les appels concurrents
  /// partagent le même téléchargement.
  Future<void> ensureFresh() {
    final age = _indexedAt == null
        ? null
        : DateTime.now().difference(_indexedAt!);
    if (age != null && age < refreshInterval) return Future.value();

    final sinceFailure = _failedAt == null
        ? null
        : DateTime.now().difference(_failedAt!);
    if (sinceFailure != null && sinceFailure < retryBackoff) {
      return Future.value();
    }

    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _refresh() async {
    if (sourceUrls.isEmpty) return;

    final merged = <String, List<XmltvProgramme>>{};
    var ok = 0;

    for (final url in sourceUrls) {
      // La source peut être le `xmltv.php` du panneau, dont l'URL porte les
      // identifiants de l'abonné en clair : ne jamais la journaliser telle
      // quelle (elle finirait dans `docker logs`). Le texte de l'exception
      // est masqué aussi, un `ClientException` recopiant l'URL demandée.
      final safeUrl = LogRedactor.redactUrl(url);
      try {
        final parsed = await _downloadAndParse(url);
        // Première source servie gagne : les suivantes ne comblent que les
        // chaînes encore absentes.
        for (final entry in parsed.entries) {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
        ok++;
        print(
          '[XmltvEpg] $safeUrl : ${parsed.length} chaînes indexées',
        );
      } catch (e) {
        print(
          '[XmltvEpg] $safeUrl : échec (${LogRedactor.redactUrl('$e')})',
        );
      }
    }

    if (ok == 0) {
      // Garder l'index précédent plutôt que de servir un guide vide.
      _failedAt = DateTime.now();
      print('[XmltvEpg] aucune source disponible, index précédent conservé');
      return;
    }

    _index = merged;
    _indexedAt = DateTime.now();
    _failedAt = null;
    print('[XmltvEpg] index prêt : ${merged.length} chaînes');
  }

  /// Télécharge [url] puis l'indexe dans un isolate dédié.
  ///
  /// Le serveur n'a qu'une boucle d'événements : décompresser et parser un
  /// dump de plusieurs milliers de chaînes dessus la gelait pendant des
  /// secondes. Plus rien d'autre ne répondait — en particulier le relais
  /// `turbo.ts`, qui cessait d'envoyer des octets au lecteur : la lecture
  /// se coupait systématiquement au démarrage, au moment précis où l'écran
  /// des chaînes demandait le guide.
  Future<Map<String, List<XmltvProgramme>>> _downloadAndParse(
    String url,
  ) async {
    final response =
        await _client.get(Uri.parse(url)).timeout(downloadTimeout);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    // Variables locales : la fermeture envoyée à l'isolate ne doit pas
    // capturer `this` (le client HTTP n'est pas transférable).
    final bytes = response.bodyBytes;
    final retention = this.retention;
    final horizon = this.horizon;
    return Isolate.run(
      () => _decodeAndParse(bytes, retention: retention, horizon: horizon),
    );
  }

  static Map<String, List<XmltvProgramme>> _decodeAndParse(
    Uint8List raw, {
    required Duration retention,
    required Duration horizon,
  }) {
    List<int> bytes = raw;
    // Beaucoup de miroirs servent du .gz sans en-tête Content-Encoding : on
    // regarde le nombre magique plutôt que de se fier aux en-têtes.
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = gzip.decode(bytes);
    }
    return _parse(
      utf8.decode(bytes, allowMalformed: true),
      retention: retention,
      horizon: horizon,
    );
  }

  /// Exposé pour les tests.
  Map<String, List<XmltvProgramme>> parseForTest(String xml) =>
      _parse(xml, retention: retention, horizon: horizon);

  static Map<String, List<XmltvProgramme>> _parse(
    String xml, {
    required Duration retention,
    required Duration horizon,
  }) {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final limit = DateTime.now().toUtc().add(horizon);
    final byChannel = <String, List<XmltvProgramme>>{};

    // Alias : plusieurs dumps déclarent <channel id="X"> avec un ou plusieurs
    // <display-name> différents de l'identifiant (« TF1 HD », « TF1 »). On
    // les indexe TOUS : seul le premier l'était, et c'était souvent la
    // variante la moins proche du nom annoncé par le panneau.
    final aliases = <String, String>{};
    final displayNames = <String>[];

    String? channelId;
    String? programmeChannel;
    DateTime? start;
    DateTime? stop;
    String? currentTag;
    final title = StringBuffer();
    final desc = StringBuffer();
    final displayName = StringBuffer();

    for (final event in parseEvents(xml)) {
      if (event is XmlStartElementEvent) {
        switch (event.name) {
          case 'channel':
            channelId = _attr(event, 'id');
            displayName.clear();
            displayNames.clear();
          case 'programme':
            programmeChannel = _attr(event, 'channel');
            start = parseXmltvDate(_attr(event, 'start'));
            stop = parseXmltvDate(_attr(event, 'stop'));
            title.clear();
            desc.clear();
          case 'title':
          case 'desc':
          case 'display-name':
            currentTag = event.name;
        }
        if (event.isSelfClosing) currentTag = null;
      } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
        final text = event is XmlTextEvent
            ? event.value
            : (event as XmlCDATAEvent).value;
        switch (currentTag) {
          case 'title':
            title.write(text);
          case 'desc':
            desc.write(text);
          case 'display-name':
            displayName.write(text);
        }
      } else if (event is XmlEndElementEvent) {
        switch (event.name) {
          case 'display-name':
            displayNames.add(displayName.toString());
            displayName.clear();
          case 'channel':
            final id = normalizeKey(channelId);
            for (final raw in displayNames) {
              final name = normalizeKey(raw);
              if (id.isNotEmpty && name.isNotEmpty && id != name) {
                aliases.putIfAbsent(name, () => id);
              }
            }
            // Clés souples (espace de noms « ~ ») : premier arrivé gagne.
            if (id.isNotEmpty) {
              for (final raw in [channelId, ...displayNames]) {
                final loose = _looseIndexKey(looseKey(raw));
                if (loose.isNotEmpty) aliases.putIfAbsent(loose, () => id);
              }
            }
            channelId = null;
          case 'programme':
            if (programmeChannel != null &&
                start != null &&
                stop != null &&
                stop.isAfter(cutoff) &&
                start.isBefore(limit)) {
              final key = normalizeKey(programmeChannel);
              if (key.isNotEmpty) {
                byChannel.putIfAbsent(key, () => []).add(
                      XmltvProgramme(
                        title: title.toString().trim(),
                        description: desc.toString().trim(),
                        start: start,
                        stop: stop,
                      ),
                    );
              }
            }
            programmeChannel = null;
            start = null;
            stop = null;
        }
        currentTag = null;
      }
    }

    for (final list in byChannel.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }

    // Rendre les chaînes atteignables aussi par leur nom affiché.
    aliases.forEach((name, id) {
      final programmes = byChannel[id];
      if (programmes != null) byChannel.putIfAbsent(name, () => programmes);
    });

    return byChannel;
  }

  static String _attr(XmlStartElementEvent event, String name) {
    for (final attribute in event.attributes) {
      if (attribute.name == name) return attribute.value;
    }
    return '';
  }

  /// Clé de correspondance : minuscules, sans ponctuation ni accents.
  ///
  /// Les dumps publics écrivent `France.2.fr` là où le panneau annonce
  /// `France2.fr` ; sans normalisation, la moitié des chaînes ne trouvent
  /// jamais leur guide.
  static String normalizeKey(String? raw) {
    if (raw == null) return '';
    final buffer = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      final folded = _accents[char] ?? char;
      if (RegExp(r'[a-z0-9]').hasMatch(folded)) buffer.write(folded);
    }
    return buffer.toString();
  }

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// « 20260811200000 +0200 » → instant UTC.
  static DateTime? parseXmltvDate(String? raw) {
    if (raw == null || raw.length < 14) return null;
    final digits = raw.substring(0, 14);
    final base = DateTime.tryParse(
      '${digits.substring(0, 4)}-${digits.substring(4, 6)}-'
      '${digits.substring(6, 8)}T${digits.substring(8, 10)}:'
      '${digits.substring(10, 12)}:${digits.substring(12, 14)}Z',
    );
    if (base == null) return null;

    final offset = raw.length >= 20 ? raw.substring(15, 20) : null;
    if (offset == null || offset.length != 5) return base;

    final sign = offset[0] == '-' ? -1 : 1;
    final hours = int.tryParse(offset.substring(1, 3));
    final minutes = int.tryParse(offset.substring(3, 5));
    if (hours == null || minutes == null) return base;

    return base.subtract(
      Duration(hours: sign * hours, minutes: sign * minutes),
    );
  }
}

class XmltvProgramme {
  const XmltvProgramme({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });

  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;

  Map<String, dynamic> toJson(String channelId) => {
        'title': title,
        'description': description,
        'start': start.toUtc().toIso8601String(),
        'end': stop.toUtc().toIso8601String(),
        'channel_id': channelId,
      };
}
