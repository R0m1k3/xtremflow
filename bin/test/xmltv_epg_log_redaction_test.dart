import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../services/xmltv_epg_service.dart';

/// URL du dump `xmltv.php` d'un panneau Xtream : les identifiants de
/// l'abonné y figurent en clair, comme en production.
const _panelUrl =
    'http://panel.example:8080/xmltv.php?username=john&password=hunter2';

/// Exécute [body] en capturant tout ce qui passe par `print`.
Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  group('XmltvEpgService — journalisation', () {
    test('masque les identifiants de l\'URL quand la source répond', () async {
      final service = XmltvEpgService(
        sourceUrls: const [_panelUrl],
        client: MockClient(
          (_) async => http.Response('<?xml version="1.0"?><tv></tv>', 200),
        ),
      );

      final lines = await _capturePrints(service.ensureFresh);
      final xmltvLines = lines.where((l) => l.startsWith('[XmltvEpg]'));

      expect(xmltvLines, isNotEmpty);
      for (final line in xmltvLines) {
        expect(line, isNot(contains('john')));
        expect(line, isNot(contains('hunter2')));
      }
      expect(
        lines,
        contains(contains('username=***&password=***')),
      );
    });

    test('masque les identifiants de l\'URL et de l\'exception en cas d\'échec',
        () async {
      // `ClientException` recopie l'URL demandée dans son message : c'est
      // par là que les identifiants fuyaient aussi.
      final service = XmltvEpgService(
        sourceUrls: const [_panelUrl],
        client: MockClient(
          (request) async => throw http.ClientException(
            'Connection refused',
            request.url,
          ),
        ),
      );

      final lines = await _capturePrints(service.ensureFresh);
      final failure = lines.firstWhere(
        (l) => l.contains('échec'),
        orElse: () => fail('aucune ligne d\'échec journalisée : $lines'),
      );

      expect(failure, isNot(contains('john')));
      expect(failure, isNot(contains('hunter2')));
      expect(failure, contains('username=***&password=***'));
      expect(failure, contains('Connection refused'));
    });
  });
}
