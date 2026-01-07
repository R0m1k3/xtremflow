import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist.dart';
import '../models/playlist_config.dart';

/// Handler for the Xtream Proxy
class ProxyHandler {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;
  static const _allowedHeaders = [
    'content-type',
    'content-length',
    'content-range',
    'transfer-encoding',
    'accept-ranges',
    'cache-control',
  ];

  ProxyHandler(this._getPlaylist);

  /// Create Xtream proxy handler with M3U8 URL rewriting support
  Handler get handler {
    return (Request request) async {
      final path = request.url.path;

      // Only handle /api/xtream/* requests
      if (!path.startsWith('api/xtream/')) {
        return Response.notFound('Not found');
      }

      // 1. Validation: Authentication (Already handled by middleware if mounted correctly, 
      // but we will ensure it's mounted under auth in server.dart)

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

        // 2. Validation: SSRF Protection via Domain Allowlist
        // We need to verify if the target domain matches the user's playlist domain
        final playlist = await _getPlaylist(request);
        if (playlist == null) {
             // If no specific playlist is contextually valid, we might need a stricter check.
             // However, for now, if we can't find a playlist associated with the user/request,
             // blocking is safer.
             return Response.forbidden('No active playlist configuration found to validate request');
        }
        
        // Normalize domains for comparison
        final targetHost = targetUrl.host.toLowerCase();
        final allowedHost = Uri.parse(playlist.dns).host.toLowerCase();

        // Allow if hosts match OR if it's a direct IP match (common in IPTV)
        // Also allow local streaming segments if they loop back (less likely here but possible)
        bool isAllowed = targetHost == allowedHost;
        
        // Strict Mode: Only allow requests to the configured DNS
        if (!isAllowed) {
            print('[Proxy] Blocked SSRF attempt to $targetHost (Allowed: $allowedHost)');
             return Response.forbidden('Access to this domain is forbidden by policy');
        }

        final proxyHeaders = {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Connection': 'keep-alive',
          // Forward relevant headers? Usually safer not to forward everything
        };

        final client = http.Client();
        final proxyRequest = http.Request(request.method, targetUrl);
        proxyRequest.headers.addAll(proxyHeaders);
        
        // Forward body if POST
        if (request.method == 'POST') {
             // For POST, we might need to read body. 
             // Xtream codes usually use GET or small POSTs. 
             // BEWARE: reading body here might buffer if not careful, 
             // but request.read() gives a stream.
             // optimizing for simple proxy:
             final bodyBytes = await request.read().toList(); // Wait for full body (usually small for API)
             proxyRequest.bodyBytes = bodyBytes.expand((i) => i).toList();
        }

        // 3. Performance: Streaming Response
        // Instead of await client.get(), we use client.send() to get a StreamedResponse
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
