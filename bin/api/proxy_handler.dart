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
  
  static const _allowedHeaders = [
    'content-type',
    'content-length',
    'content-range',
    'transfer-encoding',
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

        final targetUrl = Uri.parse(fullUrl);

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
               return Response.forbidden('No active playlist configuration found to validate request');
          }
          
          final targetHost = targetUrl.host.toLowerCase();
          final allowedHost = Uri.parse(playlist.dns).host.toLowerCase();

          if (targetHost != allowedHost) {
              print('[Proxy] Blocked SSRF attempt to $targetHost (Allowed: $allowedHost)');
               return Response.forbidden('Access to this domain is forbidden by policy');
          }
        }

        final proxyHeaders = {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Accept': '*/*',
          'Accept-Encoding': 'identity', // Explicitly request non-chunked
          'Connection': 'close', // Don't keep-alive to avoid chunked issues
        };

        final client = http.Client();
        try {
          // Use simple GET/POST instead of streaming to avoid chunked encoding issues
          http.Response response;
          if (request.method == 'POST') {
            final bodyBytes = await request.read().toList();
            final body = bodyBytes.expand((i) => i).toList();
            response = await client.post(targetUrl, headers: proxyHeaders, body: body);
          } else {
            response = await client.get(targetUrl, headers: proxyHeaders);
          }

          // Build response headers
          final responseHeaders = <String, String>{
            'access-control-allow-origin': '*',
            'content-type': response.headers['content-type'] ?? 'application/json',
          };
          
          if (response.headers['content-length'] != null) {
            responseHeaders['content-length'] = response.headers['content-length']!;
          }

          return Response(
            response.statusCode,
            body: response.bodyBytes,
            headers: responseHeaders,
          );
        } finally {
          client.close();
        }

      } catch (e, stackTrace) {
        print('Proxy error: $e');
        print(stackTrace);
        return Response.internalServerError(
          body: jsonEncode({'error': 'Proxy error', 'message': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  }
}
