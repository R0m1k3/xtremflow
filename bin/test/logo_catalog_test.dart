import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../services/logo_catalog.dart';

/// Extrait réel de `tv-logo/tv-logos/countries/france` (noms sans `-fr.png`).
const _france = {
  'bein-sports-1-french',
  'bein-sports-2-french',
  'bein-sports',
  'canal-plus',
  'canal-plus-sport',
  'canal-plus-sport-360',
  'eurosport-1',
  'france-2',
  'france-24',
  'lequipe',
  'rmc-sport-1',
  'rmc-sport-2',
  'rmc-sport-access-1',
};

void main() {
  group('matchLogoKey', () {
    String? match(String name) => matchLogoKey(name, _france);

    test('correspondance exacte après nettoyage du nom panneau', () {
      // Préfixe pays et suffixe de qualité sont du bruit propre au panneau.
      expect(match('FR - RMC SPORT 2 FHD'), 'rmc-sport-2');
      expect(match('FR: France 2 HD'), 'france-2');
      expect(match('|FR| EUROSPORT 1 UHD'), 'eurosport-1');
    });

    test('traduit le « + » de Canal+', () {
      expect(match('FR - CANAL+ SPORT FHD'), 'canal-plus-sport');
      expect(match('FR - CANAL+'), 'canal-plus');
    });

    test('accepte une variante plus longue du même identifiant', () {
      // Le dépôt nomme `bein-sports-1-french`, le panneau `BEIN SPORTS 1`.
      expect(match('FR - BEIN SPORTS 1 FHD'), 'bein-sports-1-french');
    });

    test('retombe sur la marque quand le numéro de canal est inconnu', () {
      // Les canaux événementiels (« Live 5 ») n'ont pas de logo propre :
      // celui de la marque vaut mieux qu'une tuile vide.
      expect(match('FR - RMC SPORT LIVE 5 FHD'), 'rmc-sport-1');
      expect(match('FR - CANAL+ SPORT 2'), 'canal-plus-sport');
    });

    test('ne devine pas sur un seul mot', () {
      // « France » seul ne doit pas donner le logo de France 24.
      expect(match('FR - FRANCE'), isNull);
    });

    test('rend null quand rien ne correspond', () {
      expect(match('FR - DAZN FHD'), isNull);
      expect(match(''), isNull);
    });
  });

  group('countryFolderFor', () {
    test('lit le préfixe pays du nom', () {
      expect(countryFolderFor('FR - TF1'), 'france');
      expect(countryFolderFor('BE: RTL TVI'), 'belgium');
      expect(countryFolderFor('|UK| BBC ONE'), 'united-kingdom');
    });

    test('France par défaut sans préfixe reconnu', () {
      expect(countryFolderFor('TF1 HD'), 'france');
    });
  });

  group('LogoCatalog', () {
    test('télécharge le logo apparié et le garde en cache', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode([
              {
                'name': 'rmc-sport-2-fr.png',
                'download_url': 'https://raw.example/rmc-sport-2-fr.png',
              },
              {'name': 'README.md', 'download_url': 'https://raw.example/r'},
            ]),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      });

      final catalog = LogoCatalog(client: client);
      final first = await catalog.logoFor('FR - RMC SPORT 2 FHD');
      final second = await catalog.logoFor('FR - RMC SPORT 2 FHD');

      expect(first, [1, 2, 3]);
      expect(second, [1, 2, 3]);
      // Une liste et un logo, pas un aller-retour par affichage.
      expect(requested, hasLength(2));
    });

    test('rend null sans correspondance, sans télécharger d’image', () async {
      var downloads = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(jsonEncode(const []), 200);
        }
        downloads++;
        return http.Response.bytes([1], 200);
      });

      final catalog = LogoCatalog(client: client);
      expect(await catalog.logoFor('FR - CHAINE INCONNUE'), isNull);
      expect(downloads, 0);
    });

    test('espace les tentatives quand la liste est injoignable', () async {
      var listings = 0;
      final client = MockClient((request) async {
        listings++;
        return http.Response('rate limited', 403);
      });

      final catalog = LogoCatalog(client: client);
      await catalog.logoFor('FR - RMC SPORT 2');
      await catalog.logoFor('FR - RMC SPORT 1');

      expect(listings, 1);
    });
  });
}
