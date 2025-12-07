import 'package:shelf/shelf.dart';
import 'dart:async';

/// Security Middleware Collection
/// 
/// Includes:
/// - Honeypot Routes (Trap for bots)
/// - Security Headers (HSTS, XSS Protection)
/// - Rate Limiting (Basic DoS protection)

/// 1. Security Headers Middleware
/// Adds standard security headers to every response.
Middleware securityHeadersMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      final response = await handler(request);
      
      return response.change(headers: {
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'X-XSS-Protection': '1; mode=block',
        'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        // Note: CSP is tricky with Flutter Web (requires 'unsafe-eval' for Dart),
        // so we omit it here to avoid breaking the app, or use a permissive one.
      });
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
    '/actuator/health'
  ];

  return (Handler handler) {
    return (Request request) {
      final path = request.url.path;
      
      // Check if path contains any honeypot target
      for (final trap in honeypotPaths) {
        if (path.contains(trap.replaceAll('/', ''))) { // Simple check
          print('SECURITY ALERT: Honeypot triggered by ${request.context['clientIp'] ?? 'unknown IP'} on path: $path');
          return Response.forbidden('Access Denied');
        }
      }
      
      return handler(request);
    };
  };
}

/// 3. Rate Limit Middleware (In-Memory)
/// Limits requests per IP address.
/// Default: 100 requests per minute per IP.
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
      // Identify client by IP (passed from main server or headers)
      // Note: In real prod behind Nginx, use X-Forwarded-For
      // Here we assume direct or standard setup.
      final clientIp = (request.context['clientIp'] as String?) ?? 'unknown';
      
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
