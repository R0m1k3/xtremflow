import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

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

  final http.Client _client;

  /// clé de chaîne normalisée → programmes triés par heure de début.
  Map<String, List<XmltvProgramme>> _index = {};
  DateTime? _indexedAt;
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
    for (final candidate in [channelId, displayName]) {
      final key = normalizeKey(candidate);
      if (key.isEmpty) continue;
      final hit = _index[key];
      if (hit != null && hit.isNotEmpty) return hit;
    }
    return const [];
  }

  /// Recharge l'index s'il est absent ou périmé. Les appels concurrents
  /// partagent le même téléchargement.
  Future<void> ensureFresh() {
    final age = _indexedAt == null
        ? null
        : DateTime.now().difference(_indexedAt!);
    if (age != null && age < refreshInterval) return Future.value();
    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _refresh() async {
    if (sourceUrls.isEmpty) return;

    final merged = <String, List<XmltvProgramme>>{};
    var ok = 0;

    for (final url in sourceUrls) {
      try {
        final body = await _download(url);
        final parsed = _parse(body);
        // Première source servie gagne : les suivantes ne comblent que les
        // chaînes encore absentes.
        for (final entry in parsed.entries) {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
        ok++;
        print(
          '[XmltvEpg] $url : ${parsed.length} chaînes indexées',
        );
      } catch (e) {
        print('[XmltvEpg] $url : échec ($e)');
      }
    }

    if (ok == 0) {
      // Garder l'index précédent plutôt que de servir un guide vide.
      print('[XmltvEpg] aucune source disponible, index précédent conservé');
      return;
    }

    _index = merged;
    _indexedAt = DateTime.now();
    print('[XmltvEpg] index prêt : ${merged.length} chaînes');
  }

  Future<String> _download(String url) async {
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    List<int> bytes = response.bodyBytes;
    // Beaucoup de miroirs servent du .gz sans en-tête Content-Encoding : on
    // regarde le nombre magique plutôt que de se fier aux en-têtes.
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = gzip.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Exposé pour les tests.
  Map<String, List<XmltvProgramme>> parseForTest(String xml) => _parse(xml);

  Map<String, List<XmltvProgramme>> _parse(String xml) {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final byChannel = <String, List<XmltvProgramme>>{};

    // Alias : plusieurs dumps déclarent <channel id="X"> avec un
    // <display-name> différent de l'identifiant. On indexe les deux pour
    // maximiser les correspondances.
    final aliases = <String, String>{};

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
            if (displayName.isEmpty) displayName.write(text);
        }
      } else if (event is XmlEndElementEvent) {
        switch (event.name) {
          case 'channel':
            final id = normalizeKey(channelId);
            final name = normalizeKey(displayName.toString());
            if (id.isNotEmpty && name.isNotEmpty && id != name) {
              aliases[name] = id;
            }
            channelId = null;
          case 'programme':
            if (programmeChannel != null &&
                start != null &&
                stop != null &&
                stop.isAfter(cutoff)) {
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
