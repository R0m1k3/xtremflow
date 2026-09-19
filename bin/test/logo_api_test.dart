import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../api/logo_api.dart';
import '../services/logo_catalog.dart';

/// Catalogue qui connaît uniquement `rmc-sport-2` et sert [bytes].
LogoCatalog _catalog(List<int> bytes, {void Function()? onUse}) {
  return LogoCatalog(
    client: MockClient((request) async {
      onUse?.call();
      if (request.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode([
            {
              'name': 'rmc-sport-2-fr.png',
              'download_url': 'https://raw.example/rmc-sport-2-fr.png',
            },
          ]),
          200,
        );
      }
      return http.Response.bytes(bytes, 200);
    }),
  );
}

Request _logoRequest(String src, String name) => Request(
      'GET',
      Uri.http('localhost:8089', '/api/logo', {'src': src, 'name': name}),
      headers: {'cookie': 'session=abc'},
    );

void main() {
  group('LogoApi', () {
    test('sert le logo du panneau quand il répond', () async {
      Request? forwarded;
      var catalogUsed = false;
      final api = LogoApi(
        (request) {
          forwarded = request;
          return Response.ok(
            [9, 9],
            headers: {'content-type': 'image/png'},
          );
        },
        _catalog([1], onUse: () => catalogUsed = true),
      );

      final response = await api.handle(
        _logoRequest('http://picons.example/logos/1.png', 'FR - RMC SPORT 2'),
      );

      expect(response.statusCode, 200);
      expect(await response.read().expand((b) => b).toList(), [9, 9]);
      expect(response.headers['cache-control'], contains('max-age=86400'));
      expect(catalogUsed, isFalse);
      // Le proxy reçoit l'URL au format attendu et la session du client.
      expect(forwarded!.url.path, 'api/xtream/http://picons.example/logos/1.png');
      expect(forwarded!.headers['cookie'], 'session=abc');
    });

    test('retombe sur le catalogue quand le panneau échoue', () async {
      final api = LogoApi(
        (_) => Response.notFound(null),
        _catalog([4, 2]),
      );

      final response = await api.handle(
        _logoRequest('http://picons.example/logos/1.png', 'FR - RMC SPORT 2'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'image/png');
      expect(await response.read().expand((b) => b).toList(), [4, 2]);
    });

    test('ignore une réponse panneau qui n’est pas une image', () async {
      // Page HTML de maintenance servie en 200 : pas un logo.
      final api = LogoApi(
        (_) => Response.ok('<html>', headers: {'content-type': 'text/html'}),
        _catalog([4, 2]),
      );

      final response = await api.handle(
        _logoRequest('http://picons.example/logos/1.png', 'FR - RMC SPORT 2'),
      );

      expect(await response.read().expand((b) => b).toList(), [4, 2]);
    });

    test('rend une erreur mise en cache quand rien ne correspond', () async {
      // Un statut d'erreur laisse le client afficher son icône de repli ; une
      // image vide donnait une tuile blanche. 410 et non 404 : la Cascade du
      // serveur rattrape les 404 et perdrait le cache-control.
      final api = LogoApi(
        (_) => Response.notFound(null),
        _catalog([1]),
      );

      final response = await api.handle(
        _logoRequest('http://picons.example/logos/1.png', 'FR - INCONNUE'),
      );

      expect(response.statusCode, 410);
      expect(response.headers['cache-control'], contains('max-age=600'));
    });

    test('cherche par nom quand le panneau ne fournit pas de logo', () async {
      var proxyCalled = false;
      final api = LogoApi(
        (_) {
          proxyCalled = true;
          return Response.notFound(null);
        },
        _catalog([7]),
      );

      final response = await api.handle(_logoRequest('', 'FR - RMC SPORT 2'));

      expect(response.statusCode, 200);
      expect(proxyCalled, isFalse);
    });
  });
}
