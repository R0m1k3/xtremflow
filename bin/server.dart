import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:args/args.dart';
import 'database/database.dart';
import 'api/auth_handler.dart';
import 'api/playlists_handler.dart';
import 'middleware/auth_middleware.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8089')
    ..addOption('path', defaultsTo: '/app/web');
  
  final result = parser.parse(args);
  final port = int.parse(result['port']);
  final webPath = result['path'];

  // Initialize database
  final db = AppDatabase();
  await db.init();
  await db.seedAdmin();

  // Create API handlers
  final authHandler = AuthHandler(db);
  final playlistsHandler = PlaylistsHandler(db);

  // Setup router
  final apiRouter = Router()
    // Auth endpoints (no auth middleware) - full path including /api/
    ..mount('/api/auth', authHandler.router)
    // Playlists endpoints (with auth middleware)
    ..mount('/api/playlists', Pipeline()
      .addMiddleware(authMiddleware(db))
      .addHandler(playlistsHandler.router.call));

  // Create handlers
  final staticHandler = createStaticHandler(
    webPath,
    defaultDocument: 'index.html',
    listDirectories: false,
  );

  // Main handler with API proxy
  final handler = Cascade()
    .add(_createApiHandler(apiRouter))
    .add(_createXtreamProxyHandler())
    .add(staticHandler)
    .handler;

  // Add middleware
  final pipeline = Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(_corsMiddleware())
    .addHandler(handler);

  // Start server
  final server = await shelf_io.serve(
    pipeline,
    InternetAddress.anyIPv4,
    port,
  );

  print('Server started on port ${server.port}');
  print('Serving static files from: $webPath');
  print('REST API available at: /api/auth/* and /api/playlists/*');
  print('Xtream proxy available at: /api/xtream/*');
  
  // Clean expired sessions periodically (every hour)
  Timer.periodic(const Duration(hours: 1), (_) {
    db.cleanExpiredSessions();
    print('Cleaned expired sessions');
  });
}

/// Create API handler
Handler _createApiHandler(Router apiRouter) {
  return (Request request) async {
    final path = request.url.path;
    
    // Only handle /api/* requests (excluding /api/xtream)
    if (path.startsWith('api/') && !path.startsWith('api/xtream/')) {
      return apiRouter(request);
    }
    
    return Response.notFound('Not found');
  };
}

/// CORS middleware to allow cross-origin requests
Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      // Process request and add CORS headers to response
      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

final _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
};

/// Create Xtream proxy handler with M3U8 URL rewriting support
Handler _createXtreamProxyHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /api/xtream/* requests
    if (!path.startsWith('api/xtream/')) {
      return Response.notFound('Not found');
    }

    try {
      // Extract target URL from request
      // Format: /api/xtream/http://server:port/path
      final apiPath = path.substring('api/xtream/'.length);
      
      // The client will send the full URL after /api/xtream/
      if (!apiPath.startsWith('http://') && !apiPath.startsWith('https://')) {
        return Response.badRequest(
          body: 'Invalid API URL. Expected format: /api/xtream/http://...',
        );
      }

      // Reconstruct the full target URL with query parameters
      String fullUrl = apiPath;
      if (request.url.query.isNotEmpty) {
        // If the target URL already has query params, append with &
        if (fullUrl.contains('?')) {
          fullUrl = '$fullUrl&${request.url.query}';
        } else {
          fullUrl = '$fullUrl?${request.url.query}';
        }
      }
      
      final targetUrl = Uri.parse(fullUrl);
      final baseUrl = '${targetUrl.scheme}://${targetUrl.host}${targetUrl.hasPort ? ':${targetUrl.port}' : ''}';

      print('Proxying request to: $targetUrl');

      // Use simple http.get/post with timeout
      http.Response response;
      if (request.method == 'GET') {
        response = await http.get(targetUrl).timeout(
          const Duration(seconds: 30),
          onTimeout: () => http.Response('Request timeout', 504),
        );
      } else if (request.method == 'POST') {
        final body = await request.readAsString();
        response = await http.post(targetUrl, body: body).timeout(
          const Duration(seconds: 30),
          onTimeout: () => http.Response('Request timeout', 504),
        );
      } else {
        return Response(405, body: 'Method not allowed');
      }

      // Check if this is an M3U8/HLS playlist that needs URL rewriting
      final contentType = response.headers['content-type'] ?? '';
      final isM3u8 = fullUrl.endsWith('.m3u8') || 
                     contentType.contains('application/vnd.apple.mpegurl') ||
                     contentType.contains('application/x-mpegurl') ||
                     contentType.contains('audio/mpegurl');

      if (isM3u8 && response.statusCode == 200) {
        // Rewrite URLs in M3U8 playlist to go through proxy
        final rewrittenBody = _rewriteM3u8Urls(
          response.body, 
          baseUrl, 
          targetUrl.path,
          request.requestedUri.origin,
        );
        
        print('Rewrote M3U8 playlist URLs for: $targetUrl');
        
        return Response(
          response.statusCode,
          body: rewrittenBody,
          headers: {
            'content-type': 'application/vnd.apple.mpegurl',
            'access-control-allow-origin': '*',
          },
        );
      }

      return Response(
        response.statusCode,
        body: response.bodyBytes,
        headers: {
          'content-type': response.headers['content-type'] ?? 'application/json',
          'access-control-allow-origin': '*',
        },
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

/// Rewrite URLs in M3U8 playlist to go through the proxy
/// 
/// Handles both relative and absolute URLs in HLS playlists
String _rewriteM3u8Urls(String m3u8Content, String baseUrl, String originalPath, String proxyOrigin) {
  final lines = m3u8Content.split('\n');
  final rewrittenLines = <String>[];
  
  // Get directory path for relative URL resolution
  final pathSegments = originalPath.split('/');
  pathSegments.removeLast(); // Remove filename
  final basePath = pathSegments.join('/');
  
  for (final line in lines) {
    final trimmedLine = line.trim();
    
    // Skip empty lines and comments (except URI in comments)
    if (trimmedLine.isEmpty) {
      rewrittenLines.add(line);
      continue;
    }
    
    // Handle lines that contain URLs (not starting with #, or EXT-X-KEY/EXT-X-MAP with URI)
    if (!trimmedLine.startsWith('#')) {
      // This is a segment URL
      final rewrittenUrl = _rewriteUrl(trimmedLine, baseUrl, basePath, proxyOrigin);
      rewrittenLines.add(rewrittenUrl);
    } else if (trimmedLine.contains('URI="')) {
      // Handle EXT-X-KEY, EXT-X-MAP, etc. with URI attribute
      final rewrittenLine = trimmedLine.replaceAllMapped(
        RegExp(r'URI="([^"]+)"'),
        (match) {
          final uri = match.group(1)!;
          final rewrittenUri = _rewriteUrl(uri, baseUrl, basePath, proxyOrigin);
          return 'URI="$rewrittenUri"';
        },
      );
      rewrittenLines.add(rewrittenLine);
    } else {
      rewrittenLines.add(line);
    }
  }
  
  return rewrittenLines.join('\n');
}

/// Rewrite a single URL to go through the proxy
String _rewriteUrl(String url, String baseUrl, String basePath, String proxyOrigin) {
  String fullUrl;
  
  if (url.startsWith('http://') || url.startsWith('https://')) {
    // Already absolute URL
    fullUrl = url;
  } else if (url.startsWith('/')) {
    // Absolute path, relative to server root
    fullUrl = '$baseUrl$url';
  } else {
    // Relative path, relative to current directory
    fullUrl = '$baseUrl$basePath/$url';
  }
  
  // Wrap with proxy
  return '$proxyOrigin/api/xtream/$fullUrl';
}

