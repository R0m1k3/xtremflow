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

/// Create Xtream proxy handler
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

