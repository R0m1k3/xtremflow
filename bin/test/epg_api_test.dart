import 'package:test/test.dart';
import '../api/epg_api.dart';

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
}
