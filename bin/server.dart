import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:http/http.dart' as http;
import 'package:args/args.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8089')
    ..addOption('path', defaultsTo: '/app/web');
  
  final result = parser.parse(args);
  final port = int.parse(result['port']);
  final webPath = result['path'];

  // Create handlers
  final staticHandler = createStaticHandler(
    webPath,
    defaultDocument: 'index.html',
    listDirectories: false,
  );

  // Main handler with API proxy
  final handler = Cascade()
    .add(_createApiProxyHandler())
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
  print('API proxy available at: /api/xtream/*');
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

/// Create API proxy handler
Handler _createApiProxyHandler() {
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

      final targetUrl = Uri.parse(apiPath + '?' + (request.url.query));

      print('Proxying request to: $targetUrl');

      // Forward the request
      final client = http.Client();
      try {
        final proxyRequest = http.Request(request.method, targetUrl);
        
        // Copy headers (excluding host)
        request.headers.forEach((key, value) {
          if (key.toLowerCase() != 'host') {
            proxyRequest.headers[key] = value;
          }
        });

        // Copy body if present
        if (request.method != 'GET' && request.method != 'HEAD') {
          proxyRequest.bodyBytes = await request.read().toList()
            .then((chunks) => chunks.expand((chunk) => chunk).toList());
        }

        final response = await client.send(proxyRequest);
        final responseBody = await response.stream.toBytes();

        return Response(
          response.statusCode,
          body: responseBody,
          headers: {
            'content-type': response.headers['content-type'] ?? 'application/json',
            ...response.headers,
          },
        );
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      print('Proxy error: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: 'Proxy error: $e',
      );
    }
  };
}
