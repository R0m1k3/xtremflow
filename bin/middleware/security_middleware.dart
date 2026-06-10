import 'package:shelf/shelf.dart';
import 'dart:async';
import 'dart:io';

/// Security Middleware Collection
///
/// Includes:
/// - Honeypot Routes (Trap for bots)
/// - Security Headers (HSTS, XSS Protection, CSP Report-Only)
/// - Rate Limiting (Basic DoS protection)
/// - Login-specific rate limiting (brute-force protection)

/// Resolve the real client IP.
/// Honors the first hop of X-Forwarded-For when behind nginx, otherwise
/// falls back to the socket connection info.
String clientIpOf(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final connectionInfo =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return connectionInfo?.remoteAddress.address ?? 'unknown';
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
      final path = request.url.path;

      // Check if path contains any honeypot target
      for (final trap in honeypotPaths) {
        if (path.contains(trap.replaceAll('/', ''))) { // Simple check
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
Middleware rateLimitMiddleware({int requestsPerMinute = 200}) {
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
