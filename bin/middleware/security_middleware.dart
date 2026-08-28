import 'package:shelf/shelf.dart';
import 'dart:async';
import 'dart:io';
import '../utils/log_redactor.dart';

/// Security Middleware Collection
///
/// Includes:
/// - Redacted request logging
/// - Honeypot Routes (Trap for bots)
/// - Security Headers (HSTS, XSS Protection, CSP Report-Only)
/// - Rate Limiting (Basic DoS protection)
/// - Login-specific rate limiting (brute-force protection)

/// Proxys de confiance dont l'en-tête X-Forwarded-For est honoré.
/// Par défaut : loopback et plages privées RFC1918 (le reverse proxy du
/// docker-compose parle depuis le réseau Docker). Surcharger avec
/// TRUSTED_PROXIES (liste d'IP séparées par des virgules) pour restreindre.
final List<String> _trustedProxies =
    (Platform.environment['TRUSTED_PROXIES'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

bool _isTrustedProxy(String address) {
  if (_trustedProxies.isNotEmpty) return _trustedProxies.contains(address);
  final ip = InternetAddress.tryParse(address);
  if (ip == null) return false;
  if (ip.isLoopback) return true;
  if (ip.type == InternetAddressType.IPv4) {
    final parts = ip.address.split('.').map(int.parse).toList();
    if (parts[0] == 10) return true;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    if (parts[0] == 192 && parts[1] == 168) return true;
  }
  return false;
}

/// Resolve the real client IP.
///
/// X-Forwarded-For n'est honoré que si la connexion socket provient d'un
/// proxy de confiance : sinon un client direct peut forger l'en-tête et
/// contourner le rate limit global comme la limite de tentatives de login.
String clientIpOf(Request request) {
  final connectionInfo =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  final socketAddress = connectionInfo?.remoteAddress.address;

  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null &&
      forwarded.isNotEmpty &&
      socketAddress != null &&
      _isTrustedProxy(socketAddress)) {
    return forwarded.split(',').first.trim();
  }
  return socketAddress ?? 'unknown';
}

/// 0. Redacted request logging.
///
/// Remplace `logRequests()` de shelf : le chemin `/api/xtream/<url>` embarque
/// `username`/`password` Xtream en clair dans l'URI, que le logger standard
/// écrivait tels quels — annulant l'effort de LogRedactor partout ailleurs.
Middleware redactedLogRequests() {
  return (Handler handler) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      try {
        final response = await handler(request);
        watch.stop();
        final query =
            request.requestedUri.hasQuery ? '?${request.requestedUri.query}' : '';
        print(
          '${DateTime.now().toIso8601String()} ${response.statusCode} '
          '${request.method} '
          '${LogRedactor.redactUrl('${request.requestedUri.path}$query')} '
          '(${watch.elapsedMilliseconds}ms)',
        );
        return response;
      } catch (e) {
        watch.stop();
        print(
          '${DateTime.now().toIso8601String()} ERR ${request.method} '
          '${LogRedactor.redactUrl(request.requestedUri.path)}: '
          '${LogRedactor.redactUrl('$e')}',
        );
        rethrow;
      }
    };
  };
}

/// 1. Security Headers Middleware
/// Adds standard security headers to every response.
Middleware securityHeadersMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      final response = await handler(request);

      return response.change(headers: {
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'SAMEORIGIN', // Allow embedding player.html iframes
        'X-XSS-Protection': '1; mode=block',
        'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        // Report-Only first: Flutter Web (CanvasKit/wasm) and google_fonts
        // can break under an enforcing CSP. Promote to enforcing only after
        // a clean soak with no violations in browser consoles.
        'Content-Security-Policy-Report-Only':
            "default-src 'self'; "
            "script-src 'self' 'wasm-unsafe-eval' 'unsafe-eval'; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src 'self' https://fonts.gstatic.com; "
            "img-src 'self' data: blob: https:; "
            "media-src 'self' blob:; "
            "connect-src 'self' https://fonts.gstatic.com",
      },);
    };
  };
}

/// 2. Honeypot Middleware
/// Intercepts requests to common vulnerability scanning paths.
/// Returns a 403 Forbidden immediately and logs the incident.
Middleware honeypotMiddleware() {
  // list of common bot targets
  const honeypotPaths = [
    '/admin/phpmyadmin',
    '/phpmyadmin',
    '/wp-admin',
    '/wp-login.php',
    '/.env',
    '/config.php',
    '/api/.env',
    '/console',
    '/actuator/health',
  ];

  return (Handler handler) {
    return (Request request) {
      // Comparaison sur le chemin exact ou un préfixe de segment. L'ancienne
      // comparaison `contains(trap.replaceAll('/', ''))` bloquait toute URL
      // contenant « console », « env » ou « wpadmin » n'importe où — y
      // compris des URLs proxifiées parfaitement légitimes.
      final path = '/${request.url.path}';

      for (final trap in honeypotPaths) {
        if (path == trap || path.startsWith('$trap/')) {
          print('SECURITY ALERT: Honeypot triggered by ${clientIpOf(request)} on path: $path');
          return Response.forbidden('Access Denied');
        }
      }

      return handler(request);
    };
  };
}

/// 3. Rate Limit Middleware (In-Memory)
/// Limits requests per IP address.
/// Default: 200 requests per minute per IP.
/// 600 plutôt que 200 : une grille de chaînes déclenche une requête de
/// logo et une de guide par tuile, et tous les clients partagent l'IP du
/// reverse proxy. Le plafond précédent coupait la grille en 429 au bout de
/// quelques écrans de défilement.
Middleware rateLimitMiddleware({int requestsPerMinute = 600}) {
  final clientRequests = <String, List<DateTime>>{};

  // Cleanup timer to remove old entries and prevent memory leaks
  Timer.periodic(const Duration(minutes: 5), (_) {
    final now = DateTime.now();
    clientRequests.removeWhere((_, times) {
      // Remove timestamps older than 1 minute
      times.removeWhere((t) => now.difference(t).inMinutes > 1);
      return times.isEmpty;
    });
  });

  return (Handler handler) {
    return (Request request) {
      final clientIp = clientIpOf(request);

      if (clientIp != 'unknown' && clientIp != '127.0.0.1') {
         final now = DateTime.now();

         // Get or create history for this IP
         final history = clientRequests.putIfAbsent(clientIp, () => []);

         // Clean old requests (older than 1 minute)
         history.removeWhere((t) => now.difference(t).inMinutes >= 1);

         // Check limit
         if (history.length >= requestsPerMinute) {
           print('SECURITY WARN: Rate limit exceeded for $clientIp');
           return Response(429, body: 'Too Many Requests');
         }

         // Add current request
         history.add(now);
      }

      return handler(request);
    };
  };
}

/// 4. Login Rate Limit Middleware
/// Strict per-IP limit on login attempts (brute-force protection),
/// plus a small delay on each attempt to slow credential stuffing.
Middleware loginRateLimitMiddleware({int attemptsPerMinute = 10}) {
  final attempts = <String, List<DateTime>>{};

  Timer.periodic(const Duration(minutes: 5), (_) {
    final now = DateTime.now();
    attempts.removeWhere((_, times) {
      times.removeWhere((t) => now.difference(t).inMinutes > 1);
      return times.isEmpty;
    });
  });

  return (Handler handler) {
    return (Request request) async {
      // Only throttle the login POST; other auth routes pass through
      if (!(request.method == 'POST' && request.url.path.endsWith('login'))) {
        return handler(request);
      }

      final clientIp = clientIpOf(request);
      final now = DateTime.now();
      final history = attempts.putIfAbsent(clientIp, () => []);
      history.removeWhere((t) => now.difference(t).inMinutes >= 1);

      if (history.length >= attemptsPerMinute) {
        print('SECURITY WARN: Login rate limit exceeded for $clientIp');
        return Response(429, body: 'Too many login attempts. Try again later.');
      }
      history.add(now);

      final response = await handler(request);
      if (response.statusCode == 401) {
        // Slow down brute-force attempts on failed logins
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return response;
    };
  };
}
