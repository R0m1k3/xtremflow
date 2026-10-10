import 'dart:async';
import 'dart:convert';

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

String _stamp(DateTime d) {
  final u = d.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}'
      '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
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

  group('nameKeys', () {
    // Noms réels du panneau (prod) : 59 % des chaînes françaises n'ont pas
    // d'epg_channel_id, seul leur nom permet de retrouver le guide.
    test('retire le préfixe pays et les marqueurs de qualité', () {
      expect(XmltvEpgService.nameKeys('FR - TF1 FHD ◉'), contains('tf1'));
      expect(XmltvEpgService.nameKeys('FR - FRANCE 4 FHD'), contains('france4'));
      expect(XmltvEpgService.nameKeys('|FR| M6 HD'), contains('m6'));
      expect(XmltvEpgService.nameKeys('[FR] Arte UHD 4K'), contains('arte'));
      expect(XmltvEpgService.nameKeys('FR: RMC Story HEVC'), contains('rmcstory'));
    });

    test('propose aussi la forme identifiant « nom.pays »', () {
      // Les dumps publics identifient souvent la chaîne par `TF1.fr`.
      expect(XmltvEpgService.nameKeys('FR - TF1 FHD'), contains('tf1fr'));
    });

    test('garde la variante décalée distincte de la chaîne principale', () {
      expect(XmltvEpgService.nameKeys('FR - TF1 +1 FHD'), isNot(contains('tf1')));
    });

    test('ne réduit pas un nom court à rien', () {
      expect(XmltvEpgService.nameKeys('M6'), contains('m6'));
      expect(XmltvEpgService.nameKeys('HD'), isNot(contains('')));
    });
  });

  group('correspondances élargies (chaînes vides mesurées en prod)', () {
    XmltvEpgService serviceWith(String dump) => XmltvEpgService(
          sourceUrls: const ['http://ext/epg.xml'],
          client: MockClient((_) async => http.Response.bytes(
                // Octets UTF-8 : les ids réels portent des accents.
                const Utf8Encoder().convert(dump),
                200,
              )),
        );

    String channel(String id, String name, String title, DateTime start) => '''
  <channel id="$id"><display-name>$name</display-name></channel>
  <programme start="${_stamp(start)}" stop="${_stamp(start.add(const Duration(hours: 1)))}" channel="$id"><title>$title</title></programme>''';

    test('« F3 ALPES » du panneau trouve France.3.-.Alpes.fr', () async {
      final now = DateTime.now().toUtc();
      final svc = serviceWith('<tv>${channel('France.3.-.Alpes.fr', 'France 3 Alpes', 'JT Alpes', now)}</tv>');
      final hits = await svc.programmesFor(null, displayName: 'FR - F3 ALPES HD');
      expect(hits.single.title, 'JT Alpes');
    });

    test('« AB3 » trouve AB3.Channel.fr (clé souple)', () async {
      final now = DateTime.now().toUtc();
      final svc = serviceWith('<tv>${channel('AB3.Channel.fr', 'AB3 Channel', 'Série', now)}</tv>');
      final hits = await svc.programmesFor('AB3.fr', displayName: 'FR - AB3 FHD');
      expect(hits.single.title, 'Série');
    });

    test('« TF1 +1 » reprend le guide de TF1 décalé d\'une heure', () async {
      final now = DateTime.now().toUtc();
      final svc = serviceWith('<tv>${channel('TF1.fr', 'TF1', 'Le 13h', now)}</tv>');
      final hits = await svc.programmesFor(null, displayName: 'FR - TF1 +1 FHD');
      expect(hits.single.title, 'Le 13h');
      expect(hits.single.start, now.add(const Duration(hours: 1)).copyWith(microsecond: 0, millisecond: 0));
    });

    test('une chaîne +1 qui a son propre guide le garde', () async {
      final now = DateTime.now().toUtc();
      final svc = serviceWith('<tv>'
          '${channel('Boomerang.fr', 'Boomerang', 'Normal', now)}'
          '${channel('Boomerang.+1.fr', 'Boomerang +1', 'Décalé', now)}</tv>');
      final hits = await svc.programmesFor(null, displayName: 'FR - BOOMERANG +1');
      expect(hits.single.title, 'Décalé');
    });
  });

  group('programmesFor par nom', () {
    test('trouve le guide d\'une chaîne sans epg_channel_id par son nom nettoyé',
        () async {
      final now = DateTime.now().toUtc();
      String stamp(DateTime d) {
        final u = d.toUtc();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${u.year}${two(u.month)}${two(u.day)}'
            '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
      }

      final dump = '''
<tv>
  <channel id="TF1.fr"><display-name>TF1 HD</display-name><display-name>TF1</display-name></channel>
  <programme start="${stamp(now)}" stop="${stamp(now.add(const Duration(hours: 1)))}" channel="TF1.fr">
    <title>Le 13h</title>
  </programme>
</tv>
''';
      final svc = XmltvEpgService(
        sourceUrls: const ['http://ext/epg.xml'],
        client: MockClient((_) async => http.Response(dump, 200)),
      );
      final hits = await svc.programmesFor(null, displayName: 'FR - TF1 FHD ◉');
      expect(hits.single.title, 'Le 13h');
    });

    test('indexe chaque display-name, pas seulement le premier', () {
      final now = DateTime.now().toUtc();
      final index = service.parseForTest('''
<tv>
  <channel id="x.fr"><display-name>Premier Nom</display-name><display-name>Second Nom</display-name></channel>
  <programme start="${_stamp(now)}" stop="${_stamp(now.add(const Duration(hours: 1)))}" channel="x.fr"><title>T</title></programme>
</tv>
''');
      expect(index[XmltvEpgService.normalizeKey('Second Nom')], isNotNull);
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

  group('réactivité du serveur', () {
    test('l’indexation ne gèle pas la boucle d’événements', () async {
      // Le serveur n'a qu'un isolate : décoder et parser un dump de
      // plusieurs milliers de chaînes dessus bloquait tout le reste pendant
      // des secondes — y compris le relais `turbo.ts` des flux en cours,
      // d'où des coupures systématiques au démarrage de la lecture.
      final now = DateTime.now().toUtc();
      String stamp(DateTime d) {
        String two(int v) => v.toString().padLeft(2, '0');
        return '${d.year}${two(d.month)}${two(d.day)}'
            '${two(d.hour)}${two(d.minute)}${two(d.second)} +0000';
      }

      // Volume d'un vrai dump de panneau : ~7000 chaînes, résumés de
      // plusieurs phrases.
      final desc = 'Résumé du programme, avec assez de texte pour peser '
          'comme un vrai guide. ' * 4;
      final xml = StringBuffer('<?xml version="1.0"?><tv>');
      for (var c = 0; c < 7000; c++) {
        xml.write('<channel id="Chaine.$c.fr">'
            '<display-name>FR - CHAINE $c</display-name></channel>');
        for (var p = 0; p < 30; p++) {
          final start = now.add(Duration(minutes: 30 * p));
          final stop = start.add(const Duration(minutes: 30));
          xml.write('<programme start="${stamp(start)}" '
              'stop="${stamp(stop)}" channel="Chaine.$c.fr">'
              '<title>Programme $p</title><desc>$desc</desc>'
              '</programme>');
        }
      }
      xml.write('</tv>');
      final body = xml.toString();

      final service = XmltvEpgService(
        sourceUrls: const ['http://dump.example/epg.xml'],
        client: MockClient((_) async => http.Response(body, 200)),
      );

      // Un « battement » toutes les 10 ms : le plus long écart observé est
      // le temps pendant lequel la boucle d'événements est restée bloquée.
      var last = DateTime.now();
      var worstGap = Duration.zero;
      final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        final gap = now.difference(last);
        if (gap > worstGap) worstGap = gap;
        last = now;
      });

      await service.ensureFresh();
      heartbeat.cancel();
      // Le dernier blocage n'est suivi d'aucun battement : le compter aussi.
      final tail = DateTime.now().difference(last);
      if (tail > worstGap) worstGap = tail;

      expect(service.channelCount, greaterThanOrEqualTo(7000));
      expect(
        worstGap,
        lessThan(const Duration(milliseconds: 250)),
        reason: 'boucle d’événements gelée ${worstGap.inMilliseconds} ms',
      );
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
