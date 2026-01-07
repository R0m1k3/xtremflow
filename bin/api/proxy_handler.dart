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
      // CRITICAL: Check path BEFORE auth so non-proxy requests fall through to static handler
      if (!path.startsWith('api/xtream/')) {
        // Return 404 so Cascade tries next handler (staticHandler)
        return Response.notFound('Not an xtream proxy request');
      }

      // === AUTHENTICATION (applied only for /api/xtream/* requests) ===
      final token = _extractToken(request);
      if (token == null) {
        return Response(401, body: 'Unauthorized');
      }

      final session = _db.findSessionByToken(token);
      if (session == null) {
        return Response(401, body: 'Invalid or expired session');
      }

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

        // SSRF Protection via Domain Allowlist
        final playlist = await _getPlaylist(request);
        if (playlist == null) {
             return Response.forbidden('No active playlist configuration found to validate request');
        }
        
        // Normalize domains for comparison
        final targetHost = targetUrl.host.toLowerCase();
        final allowedHost = Uri.parse(playlist.dns).host.toLowerCase();

        bool isAllowed = targetHost == allowedHost;
        
        if (!isAllowed) {
            print('[Proxy] Blocked SSRF attempt to $targetHost (Allowed: $allowedHost)');
             return Response.forbidden('Access to this domain is forbidden by policy');
        }

        final proxyHeaders = {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Connection': 'keep-alive',
        };

        final client = http.Client();
        final proxyRequest = http.Request(request.method, targetUrl);
        proxyRequest.headers.addAll(proxyHeaders);
        
        // Forward body if POST
        if (request.method == 'POST') {
             final bodyBytes = await request.read().toList();
             proxyRequest.bodyBytes = bodyBytes.expand((i) => i).toList();
        }

        // Streaming Response
        final streamedResponse = await client.send(proxyRequest);

        // Filter headers
        final responseHeaders = <String, String>{
          'access-control-allow-origin': '*',
        };
        
        streamedResponse.headers.forEach((key, value) {
            if (_allowedHeaders.contains(key.toLowerCase())) {
                responseHeaders[key] = value;
            }
        });

        // Pipe the stream directly to the response
        return Response(
          streamedResponse.statusCode,
          body: streamedResponse.stream,
          headers: responseHeaders,
        );

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
