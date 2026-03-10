import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist.dart';
import '../models/playlist_config.dart';
import '../database/database.dart';

/// Handler for the Xtream Proxy
class ProxyHandler {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;
  final AppDatabase _db;
  final http.Client _client = http.Client();

  static const _allowedHeaders = [
    'content-type',
    'content-range',
    'accept-ranges',
    'cache-control',
  ];

  ProxyHandler(this._getPlaylist, this._db);

  /// Extract token from Authorization header or cookie
  String? _extractToken(Request request) {
    // Try Authorization header first
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }

    // Try cookie
    final cookie = request.headers['cookie'];
    if (cookie != null) {
      final parts = cookie.split(';');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith('session=')) {
          return trimmed.substring(8);
        }
      }
    }

    return null;
  }

  /// Create Xtream proxy handler with M3U8 URL rewriting support
  Handler get handler {
    return (Request request) async {
      final path = request.url.path;

      // Only handle /api/xtream/* requests
      // CRITICAL: Check path BEFORE anything else so non-proxy requests fall through to static handler
      if (!path.startsWith('api/xtream/')) {
        // Return 404 so Cascade tries next handler (staticHandler)
        return Response.notFound('Not an xtream proxy request');
      }

      // NOTE: Authentication REMOVED from proxy to allow browser-initiated requests (img src, etc.)
      // SSRF protection is still active via domain validation below.

      Uri? targetUrl;

      // === PROXY LOGIC ===
      try {
        // Extract target URL from request
        // Format: /api/xtream/http://server:port/path
        String apiPath = path.substring('api/xtream/'.length);

        // Decode URL if it's encoded
        if (apiPath.startsWith('http%3A') || apiPath.startsWith('https%3A')) {
          apiPath = Uri.decodeComponent(apiPath);
        }

        if (!apiPath.startsWith('http://') && !apiPath.startsWith('https://')) {
          return Response.badRequest(
            body: 'Invalid API URL. Expected format: /api/xtream/http://...',
          );
        }

        String fullUrl = apiPath;
        if (request.url.query.isNotEmpty) {
          if (fullUrl.contains('?')) {
            fullUrl = '$fullUrl&${request.url.query}';
          } else {
            fullUrl = '$fullUrl?${request.url.query}';
          }
        }

        targetUrl = Uri.parse(fullUrl);

        // SSRF Protection - but allow images/static assets from any host
        // Xtream providers often use separate CDN servers for picons/images
        final isStaticAsset = targetUrl.path.endsWith('.png') ||
            targetUrl.path.endsWith('.jpg') ||
            targetUrl.path.endsWith('.jpeg') ||
            targetUrl.path.endsWith('.gif') ||
            targetUrl.path.endsWith('.webp') ||
            targetUrl.path.endsWith('.ico') ||
            targetUrl.path.contains('/picons/') ||
            targetUrl.path.contains('/logos/');

        if (!isStaticAsset) {
          // For API calls, enforce domain allowlist
          final playlist = await _getPlaylist(request);
          if (playlist == null) {
            return Response.forbidden(
                'No active playlist configuration found to validate request');
          }

          final targetHost = targetUrl.host.toLowerCase();
          final allowedHost = Uri.parse(playlist.dns).host.toLowerCase();

          if (targetHost != allowedHost) {
            print(
                '[Proxy] Blocked SSRF attempt to $targetHost (Allowed: $allowedHost)');
            return Response.forbidden(
                'Access to this domain is forbidden by policy');
          }
        }

        final proxyHeaders = <String, String>{
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Connection': 'close', // Forced close for better IPTV server compatibility
        };

        // Forward Range header if present
        if (request.headers['range'] != null) {
          proxyHeaders['range'] = request.headers['range']!;
        }

        try {
          print('[Proxy] Forwarding to: $targetUrl');
          final proxyRequest = http.Request(request.method, targetUrl);
          proxyRequest.headers.addAll(proxyHeaders);
          proxyRequest.followRedirects = true;

          if (request.method == 'POST') {
            final bodyBytes = await request.read().toList();
            proxyRequest.bodyBytes = bodyBytes.expand((i) => i).toList();
          }

          // Added 90s timeout to allow frontend (60s) to time out gracefully first
          final response = await _client
              .send(proxyRequest)
              .timeout(const Duration(seconds: 90));

          // Build response headers from source response
          final responseHeaders = <String, String>{
            'access-control-allow-origin': '*',
          };

          // Forward specific safe headers
          for (final header in _allowedHeaders) {
            if (response.headers.containsKey(header)) {
              responseHeaders[header] = response.headers[header]!;
            }
          }

          // ALWAYS stream the response for maximum performance and to avoid memory issues with large JSONs
          return Response(
            response.statusCode,
            body: response.stream,
            headers: responseHeaders,
          );
        } catch (e) {
          rethrow;
        }
      } catch (e) {
        print('[ProxyHandler] error on $path: $e');

        // Return transparent 1x1 pixel image fallback for images
        if (targetUrl?.path.endsWith('.png') == true ||
            targetUrl?.path.endsWith('.jpg') == true) {
          return Response.ok(
            base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='),
            headers: {'content-type': 'image/png'},
          );
        }

        return Response.internalServerError(
          body: jsonEncode({'error': 'Proxy error', 'message': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  }
}
