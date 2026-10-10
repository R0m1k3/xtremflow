import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../api/epg_api.dart';
import '../models/playlist_config.dart';
import '../services/xmltv_epg_service.dart';

/// Extrait réel d'une réponse `get_simple_data_table` (panneau Xtream) :
/// titres/descriptions en base64, horodatages epoch UTC doublés d'une chaîne
/// exprimée dans le fuseau du panneau — ici Europe/Amsterdam (UTC+2).
const _sampleListing = {
  'epg_listings': [
    {
      'id': '336987829',
      'epg_id': '104',
      'title': 'Sm91cm5hbCBkZSAyMGg=', // "Journal de 20h"
      'lang': '',
      'start': '2026-08-11 20:00:00',
      'end': '2026-08-11 20:35:00',
      'description': 'TCdpbmZvIGR1IHNvaXI=', // "L'info du soir"
      'channel_id': 'TF1.fr',
      'start_timestamp': '1786471200', // 2026-08-11T18:00:00Z
      'stop_timestamp': '1786473300', // 2026-08-11T18:35:00Z
    },
  ],
};

void main() {
  final api = EpgApi((_) async => null);

  group('transformEpgData', () {
    test('convertit les horodatages epoch en ISO-8601 UTC', () {
      final result = api.transformEpgData(_sampleListing, '845452');
      final programme = (result['programmes'] as List).single as Map;

      // Sans cette conversion, le client relisait « 2026-08-11T20:00:00 »
      // comme de l'heure locale et décalait tout le guide de 2 h.
      expect(programme['start'], '2026-08-11T18:00:00.000Z');
      expect(programme['end'], '2026-08-11T18:35:00.000Z');
    });

    test('décode les titres et descriptions base64', () {
      final result = api.transformEpgData(_sampleListing, '845452');
      final programme = (result['programmes'] as List).single as Map;

      expect(programme['title'], 'Journal de 20h');
      expect(programme['description'], "L'info du soir");
      expect(programme['channel_id'], '845452');
    });

    test('retombe sur les champs texte quand les epoch manquent', () {
      final result = api.transformEpgData({
        'epg_listings': [
          {
            'title': 'Sm91cm5hbCBkZSAyMGg=',
            'start': '2026-08-11 20:00:00',
            'stop': '2026-08-11 20:35:00',
          },
        ],
      }, '845452');
      final programme = (result['programmes'] as List).single as Map;

      expect(programme['start'], '2026-08-11T20:00:00');
      expect(programme['end'], '2026-08-11T20:35:00');
    });

    test('rend une liste vide sur un payload sans epg_listings', () {
      // Ce que renvoie un panneau qui ne connaît pas l'action demandée :
      // un 200 contenant le bloc d'authentification.
      final result = api.transformEpgData({
        'user_info': {'auth': 1},
        'server_info': {'url': 'tit.example'},
      }, '845452');

      expect(result['programmes'], isEmpty);
    });
  });

  group('handleGetEpg', () {
    final playlist = PlaylistConfig(
      id: 'p1',
      name: 'Test',
      dns: 'http://panel.example',
      username: 'u',
      password: 'p',
      createdAt: DateTime(2026, 1, 1),
    );

    String xmltvDump(DateTime start, DateTime stop) {
      String stamp(DateTime d) {
        final u = d.toUtc();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${u.year}${two(u.month)}${two(u.day)}'
            '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
      }

      return '''
<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="France2.fr"><display-name>FRANCE 2</display-name></channel>
  <programme start="${stamp(start)}" stop="${stamp(stop)}" channel="France2.fr">
    <title lang="fr">Journal de 20h</title>
    <desc lang="fr">L'info du soir</desc>
  </programme>
</tv>
''';
    }

    Request requestFor(String channelId) =>
        Request('GET', Uri.parse('http://localhost/api/epg/$channelId'));

    test('sert le guide depuis le dump XMLTV du panneau, sans appel par '
        'chaîne', () async {
      // Un appel `player_api` par chaîne coûte plusieurs secondes chez le
      // fournisseur : le dump du panneau couvre toutes les chaînes d'un coup.
      final now = DateTime.now().toUtc();
      final actions = <String>[];

      final client = MockClient((request) async {
        final url = request.url;
        if (url.path.endsWith('/xmltv.php')) {
          return http.Response(
            xmltvDump(now.subtract(const Duration(minutes: 5)),
                now.add(const Duration(minutes: 25))),
            200,
          );
        }
        final action = url.queryParameters['action'] ?? '';
        actions.add(action);
        if (action == 'get_live_streams') {
          return http.Response(
            jsonEncode([
              {
                'stream_id': 845452,
                'name': 'FRANCE 2',
                'epg_channel_id': 'France2.fr',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final api = EpgApi(
        (_) async => playlist,
        httpClient: client,
        panelXmltvBuilder: (config) => XmltvEpgService(
          sourceUrls: ['${config.dns}/xmltv.php'],
          client: client,
        ),
      );

      final response = await api.handleGetEpg(requestFor('845452'), '845452');
      final body = jsonDecode(await response.readAsString()) as Map;

      expect(response.statusCode, 200);
      expect((body['programmes'] as List).single['title'], 'Journal de 20h');
      expect(response.headers['X-Epg-Source'], 'panel-xmltv');
      // Seule la table des chaînes est interrogée : aucune action EPG.
      expect(actions, ['get_live_streams']);
    });

    test('retombe sur player_api quand le dump ne couvre pas la chaîne',
        () async {
      final actions = <String>[];
      // Heure locale volontairement : le panneau émet des horodatages sans
      // fuseau, que le serveur relit comme de l'heure locale.
      final future = DateTime.now().add(const Duration(minutes: 10));
      String panelStamp(DateTime d) =>
          d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');

      final client = MockClient((request) async {
        final url = request.url;
        if (url.path.endsWith('/xmltv.php')) {
          return http.Response('<tv></tv>', 200);
        }
        final action = url.queryParameters['action'] ?? '';
        actions.add(action);
        if (action == 'get_live_streams') {
          return http.Response(jsonEncode(const []), 200);
        }
        if (action == 'get_simple_data_table') {
          return http.Response(
            jsonEncode({
              'epg_listings': [
                {
                  'title': base64Encode(utf8.encode('Match')),
                  'description': '',
                  'start': panelStamp(future),
                  'end': panelStamp(future.add(const Duration(hours: 2))),
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final api = EpgApi(
        (_) async => playlist,
        httpClient: client,
        panelXmltvBuilder: (config) => XmltvEpgService(
          sourceUrls: ['${config.dns}/xmltv.php'],
          client: client,
        ),
      );

      final response = await api.handleGetEpg(requestFor('999'), '999');
      final body = jsonDecode(await response.readAsString()) as Map;

      expect((body['programmes'] as List).single['title'], 'Match');
      expect(response.headers['X-Epg-Source'], 'xtream');
      expect(actions, contains('get_simple_data_table'));
    });

    // Dump externe couvrant TF1, et panneau dont le xmltv.php est vide.
    String externalDump() {
      final now = DateTime.now().toUtc();
      return xmltvDump(now, now.add(const Duration(hours: 1)))
          .replaceAll('France2.fr', 'TF1.fr')
          .replaceAll('FRANCE 2', 'TF1');
    }

    EpgApi apiWith(http.Client client) => EpgApi(
          (_) async => playlist,
          httpClient: client,
          xmltv: XmltvEpgService(
            sourceUrls: const ['http://ext.example/epg.xml'],
            client: client,
          ),
          panelXmltvBuilder: (config) => XmltvEpgService(
            sourceUrls: ['${config.dns}/xmltv.php'],
            client: client,
          ),
        );

    test('un panneau qui plante ne prive plus la chaîne du dump externe',
        () async {
      // Constaté en prod : chaque /api/epg répondait 500 en 4 s, le guide
      // externe (qui couvrait pourtant la chaîne) n'étant jamais consulté.
      final client = MockClient((request) async {
        final url = request.url;
        if (url.host == 'ext.example') return http.Response(externalDump(), 200);
        if (url.path.endsWith('/xmltv.php')) return http.Response('<tv></tv>', 200);
        final action = url.queryParameters['action'] ?? '';
        if (action == 'get_live_streams') {
          return http.Response(
            jsonEncode([
              {'stream_id': 1, 'name': 'FR - TF1 FHD ◉', 'epg_channel_id': ''},
            ]),
            200,
          );
        }
        throw http.ClientException('Connection closed', url);
      });

      final response = await apiWith(client).handleGetEpg(requestFor('1'), '1');
      final body = jsonDecode(await response.readAsString()) as Map;

      expect(response.statusCode, 200);
      expect(response.headers['X-Epg-Source'], 'xmltv');
      expect((body['programmes'] as List).single['title'], 'Journal de 20h');
    });

    test('le dump externe passe avant l\'appel lent chaîne par chaîne',
        () async {
      final actions = <String>[];
      final client = MockClient((request) async {
        final url = request.url;
        if (url.host == 'ext.example') return http.Response(externalDump(), 200);
        if (url.path.endsWith('/xmltv.php')) return http.Response('<tv></tv>', 200);
        final action = url.queryParameters['action'] ?? '';
        actions.add(action);
        if (action == 'get_live_streams') {
          return http.Response(
            jsonEncode([
              {'stream_id': 1, 'name': 'TF1', 'epg_channel_id': 'TF1.fr'},
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final response = await apiWith(client).handleGetEpg(requestFor('1'), '1');
      expect(response.headers['X-Epg-Source'], 'xmltv');
      expect(actions, isNot(contains('get_simple_data_table')));
    });

    test('la grille entière partage un seul téléchargement de la table',
        () async {
      // 30 tuiles demandent leur guide d'un coup : sans mutualisation, autant
      // de `get_live_streams` (7 Mo en prod) partaient en parallèle.
      var liveStreamsCalls = 0;
      final client = MockClient((request) async {
        final url = request.url;
        if (url.host == 'ext.example') return http.Response(externalDump(), 200);
        if (url.path.endsWith('/xmltv.php')) return http.Response('<tv></tv>', 200);
        final action = url.queryParameters['action'] ?? '';
        if (action == 'get_live_streams') {
          liveStreamsCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode([
              for (var i = 1; i <= 5; i++)
                {'stream_id': i, 'name': 'TF1', 'epg_channel_id': 'TF1.fr'},
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final api = apiWith(client);
      final responses = await Future.wait([
        for (var i = 1; i <= 5; i++) api.handleGetEpg(requestFor('$i'), '$i'),
      ]);
      expect(responses.every((r) => r.statusCode == 200), isTrue);
      expect(liveStreamsCalls, 1);
    });
  });
}
