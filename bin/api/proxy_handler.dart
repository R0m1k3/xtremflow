import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist_config.dart';
import '../utils/log_redactor.dart';

/// Returns true when [host] must never be proxied (loopback, private LAN,
/// link-local/cloud-metadata ranges) — SSRF protection for asset URLs that
/// bypass the playlist-domain allowlist.
bool isForbiddenProxyHost(String host) {
  final lower = host.toLowerCase();
  if (lower == 'localhost' || lower == '::1') return true;

  final ip = InternetAddress.tryParse(lower);
  if (ip == null) return false; // Hostname: validated by domain allowlist path

  if (ip.isLoopback || ip.isLinkLocal) return true;
  if (ip.type == InternetAddressType.IPv4) {
    final parts = ip.address.split('.').map(int.parse).toList();
    if (parts[0] == 10) return true; // 10.0.0.0/8
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    if (parts[0] == 192 && parts[1] == 168) return true; // 192.168.0.0/16
    if (parts[0] == 169 && parts[1] == 254) return true; // metadata/link-local
    if (parts[0] == 0) return true;
  }
  return false;
}

/// Handler for the Xtream Proxy
class ProxyHandler {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;
  final http.Client _client = http.Client();

  final Map<String, (PlaylistConfig, DateTime)> _playlistCache = {};
  static const _cacheDuration = Duration(minutes: 5);

  static const _allowedHeaders = [
    'content-type',
    'content-range',
    'accept-ranges',
    'cache-control',
    'server',
    'date',
  ];

  static const _allowedRequestHeaders = [
    'user-agent',
    'accept',
    'range',
    'referer',
  ];

  Future<PlaylistConfig?> _getCachedPlaylist(Request request) async {
    // Basic caching to avoid DB overhead on every video segment
    final now = DateTime.now();
    const cacheKey =
        'global_playlist'; // Currently app has one primary playlist per user/global

    if (_playlistCache.containsKey(cacheKey)) {
      final (cached, expiry) = _playlistCache[cacheKey]!;
      if (now.isBefore(expiry)) return cached;
    }

    final playlist = await _getPlaylist(request);
    if (playlist != null) {
      _playlistCache[cacheKey] = (playlist, now.add(_cacheDuration));
    }
    return playlist;
  }

  ProxyHandler(this._getPlaylist);

  /// Create Xtream proxy handler with M3U8 URL rewriting support
  Handler get handler {
    return (Request request) async {
      final path = request.url.path;

      // Only handle /api/xtream/* requests
      // CRITICAL: Check path BEFORE anything else so non-proxy requests fall through to static handler
      if (!path.startsWith('api/xtream/')) {
        // Return 404 so Cascade tries next handler (streamingRouter)
        return Response.notFound(null);
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

        // Only plain http(s) may be proxied
        if (targetUrl.scheme != 'http' && targetUrl.scheme != 'https') {
          return Response.forbidden('Unsupported URL scheme');
        }

        // Never proxy to loopback/private/link-local targets (SSRF)
        if (isForbiddenProxyHost(targetUrl.host)) {
          print('[Proxy] Blocked SSRF attempt to private host: ${targetUrl.host}');
          return Response.forbidden('Access to this host is forbidden');
        }

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
          final playlist = await _getCachedPlaylist(request);
          if (playlist == null) {
            return Response.forbidden(
              'No active playlist configuration found to validate request',
            );
          }

          final targetHost = targetUrl.host.toLowerCase();
          final allowedHost = Uri.parse(playlist.dns).host.toLowerCase();

          if (targetHost != allowedHost) {
            print(
              '[Proxy] Blocked SSRF attempt to $targetHost (Allowed: $allowedHost)',
            );
            return Response.forbidden(
              'Access to this domain is forbidden by policy',
            );
          }
        }

        final proxyHeaders = <String, String>{
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Keep-Alive': 'timeout=30, max=100', // Request persistent connection
        };

        // Forward Range header if present
        if (request.headers['range'] != null) {
          proxyHeaders['range'] = request.headers['range']!;
        }

        try {
          print('[Proxy] Forwarding to: ${LogRedactor.redactUrl(targetUrl.toString())}');
          final proxyRequest = http.Request(request.method, targetUrl);

          // Forward safe request headers
          for (final header in _allowedRequestHeaders) {
            if (request.headers.containsKey(header)) {
              proxyHeaders[header] = request.headers[header]!;
            }
          }

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
            'connection': 'keep-alive',
            'keep-alive': 'timeout=30',
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
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
            ),
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
