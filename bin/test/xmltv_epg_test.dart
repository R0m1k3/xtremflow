import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../services/xmltv_epg_service.dart';

/// Extrait représentatif d'un dump XMLTV public : décalage horaire explicite,
/// identifiant ponctué côté source là où le panneau annonce `France2.fr`, et
/// un `display-name` distinct de l'identifiant.
String _fixture(DateTime start, DateTime stop) {
  String stamp(DateTime d) {
    final u = d.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}'
        '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
  }

  return '''
<?xml version="1.0" encoding="utf-8" ?>
<tv>
  <channel id="France.2.fr"><display-name>FR - FRANCE 2</display-name></channel>
  <programme start="${stamp(start)}" stop="${stamp(stop)}" channel="France.2.fr">
    <title lang="fr">Journal de 20h</title>
    <desc lang="fr">L'info du soir</desc>
  </programme>
</tv>
''';
}

void main() {
  final service = XmltvEpgService(sourceUrls: const []);

  group('normalizeKey', () {
    test('rapproche les identifiants ponctués différemment', () {
      // Le cœur du repli : sans cette normalisation, `France2.fr` du panneau
      // et `France.2.fr` du dump ne se rencontrent jamais.
      expect(
        XmltvEpgService.normalizeKey('France2.fr'),
        XmltvEpgService.normalizeKey('France.2.fr'),
      );
    });

    test('replie la casse et les accents', () {
      expect(XmltvEpgService.normalizeKey('Chérie 25'), 'cherie25');
    });

    test('rend une clé vide sur une entrée nulle ou sans caractère utile', () {
      expect(XmltvEpgService.normalizeKey(null), '');
      expect(XmltvEpgService.normalizeKey('...'), '');
    });
  });

  group('parseXmltvDate', () {
    test('applique le décalage horaire annoncé', () {
      expect(
        XmltvEpgService.parseXmltvDate('20260811200000 +0200'),
        DateTime.utc(2026, 8, 11, 18),
      );
    });

    test('traite une date sans décalage comme de l UTC', () {
      expect(
        XmltvEpgService.parseXmltvDate('20260811200000'),
        DateTime.utc(2026, 8, 11, 20),
      );
    });

    test('rejette une valeur tronquée', () {
      expect(XmltvEpgService.parseXmltvDate('202608'), isNull);
    });
  });

  group('parse', () {
    test('indexe un programme en cours et décode son titre', () {
      final now = DateTime.now().toUtc();
      final index = service.parseForTest(
        _fixture(
          now.subtract(const Duration(minutes: 10)),
          now.add(const Duration(minutes: 20)),
        ),
      );

      final programmes = index[XmltvEpgService.normalizeKey('France2.fr')];
      expect(programmes, isNotNull);
      expect(programmes!.single.title, 'Journal de 20h');
      expect(programmes.single.description, "L'info du soir");
    });

    test('rend la chaîne atteignable par son nom affiché', () {
      final now = DateTime.now().toUtc();
      final index = service.parseForTest(
        _fixture(now, now.add(const Duration(minutes: 20))),
      );

      expect(index[XmltvEpgService.normalizeKey('FR - FRANCE 2')], isNotNull);
    });

    test('écarte les programmes terminés hors fenêtre de rétention', () {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 2));
      final index = service.parseForTest(
        _fixture(old, old.add(const Duration(minutes: 30))),
      );

      expect(index, isEmpty);
    });
  });

  group('ensureFresh', () {
    test('ne retélécharge pas tant que l’index est frais', () async {
      final now = DateTime.now().toUtc();
      var calls = 0;
      final service = XmltvEpgService(
        sourceUrls: const ['http://dump.example/epg.xml'],
        client: MockClient((_) async {
          calls++;
          return http.Response(
            _fixture(now, now.add(const Duration(minutes: 30))),
            200,
          );
        }),
      );

      await service.ensureFresh();
      await service.ensureFresh();

      expect(calls, 1);
      expect(service.hasData, isTrue);
    });

    test('espace les tentatives après un échec', () async {
      // Sans ce recul, une source morte était retéléchargée à chaque
      // consultation du guide : une requête sortante par chaîne affichée.
      var calls = 0;
      final service = XmltvEpgService(
        sourceUrls: const ['http://dump.example/epg.xml'],
        retryBackoff: const Duration(minutes: 15),
        client: MockClient((_) async {
          calls++;
          return http.Response('nope', 500);
        }),
      );

      await service.ensureFresh();
      await service.ensureFresh();
      await service.ensureFresh();

      expect(calls, 1);
      expect(service.hasData, isFalse);
    });
  });

  group('horizon', () {
    test('écarte les programmes au-delà de l’horizon d’indexation', () {
      // Un dump national couvre sept jours : tout garder ferait grossir
      // l'index pour un guide qui n'affiche que le programme courant.
      final service = XmltvEpgService(
        sourceUrls: const [],
        horizon: const Duration(hours: 48),
      );
      final far = DateTime.now().toUtc().add(const Duration(days: 5));

      expect(
        service.parseForTest(_fixture(far, far.add(const Duration(hours: 1)))),
        isEmpty,
      );
    });
  });
}
