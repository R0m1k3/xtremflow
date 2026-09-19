import 'package:shelf/shelf.dart';

import '../services/logo_catalog.dart';
import 'asset_failure_cache.dart';

/// GET /api/logo?src=<stream_icon>&name=<nom de chaîne>
///
/// Logo d'une chaîne, avec repli. L'URL fournie par le panneau est tentée
/// d'abord, via le proxy Xtream (mêmes protections anti-SSRF, même mémoire
/// des hôtes morts). En cas d'échec, le logo est cherché par nom dans le
/// dépôt public `tv-logos`.
///
/// POURQUOI : quand l'hébergeur de picons du revendeur tombe, toute la grille
/// perd ses logos d'un coup, alors que les autres applications IPTV les
/// affichent encore grâce à leurs propres sources de repli.
class LogoApi {
  LogoApi(this._proxy, this._catalog);

  /// Proxy Xtream (`ProxyHandler.handler`), qui attend `/api/xtream/<url>`.
  final Handler _proxy;

  final LogoCatalog _catalog;

  /// Un logo trouvé change rarement : un jour de cache navigateur.
  static const _found = 'public, max-age=86400';

  Future<Response> handle(Request request) async {
    final src = request.url.queryParameters['src'] ?? '';
    final name = request.url.queryParameters['name'] ?? '';

    // Une URL panneau malformée ne doit pas priver la chaîne du repli.
    final proxied = src.startsWith('http://') || src.startsWith('https://')
        ? Uri.tryParse('${request.requestedUri.origin}/api/xtream/$src')
        : null;

    if (proxied != null) {
      final upstream = await _proxy(
        Request(
          'GET',
          proxied,
          headers: {
            for (final header in const ['cookie', 'authorization'])
              if (request.headers[header] != null)
                header: request.headers[header]!,
          },
        ),
      );

      final type = upstream.headers['content-type'] ?? '';
      if (upstream.statusCode == 200 && type.startsWith('image/')) {
        return Response.ok(
          upstream.read(),
          headers: {'content-type': type, 'cache-control': _found},
        );
      }
      // Corps d'erreur consommé : sinon la connexion amont reste ouverte.
      await upstream.read().drain<void>();
    }

    if (name.isNotEmpty) {
      final bytes = await _catalog.logoFor(name);
      if (bytes != null) {
        return Response.ok(
          bytes,
          headers: {'content-type': 'image/png', 'cache-control': _found},
        );
      }
    }

    return missingImageResponse();
  }
}
