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
import 'models/user.dart';
import 'models/playlist.dart';
import 'models/playlist_config.dart';
import 'api/auth_handler.dart';
import 'api/users_handler.dart';
import 'api/playlists_handler.dart';
import 'api/settings_handler.dart';
import 'api/streaming_handler.dart';
import 'api/proxy_handler.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/security_middleware.dart';
import 'services/cleanup_service.dart';

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

  // Initialize Streaming Subsystem
  await initStreaming();

  // Helper to get playlist from request
  Future<PlaylistConfig?> getPlaylist(Request request) async {
    Playlist? playlist;

    final user = request.context['user'] as User?;
    // If we have a user from auth middleware, prefer their playlists
    if (user != null) {
      final playlists = db.getPlaylists(user.id);
      if (playlists.isNotEmpty) playlist = playlists.first;
    } else {
      // Fallback: This leg should effectively be unreachable for /api/xtream if we use authMiddleware,
      // but might be used by other handlers or if auth is optional somewhere.
      // For VOD/Live which currently might not have auth (URL tokenizing is complex), we keep fallback?
      // WAIT: The plan said "Secure /api/xtream using authMiddleware".
      // If we do that, user is GUARANTEED for proxy.
      // But for /api/live and /api/vod, we might need a different strategy (token in URL).
      // For now, let's keep the fallback logic for non-proxy parts if any.
      final users = db.getAllUsers();
      if (users.isNotEmpty) {
        final playlists = db.getPlaylists(users[0].id);
        if (playlists.isNotEmpty) playlist = playlists.first;
      }
    }

    if (playlist != null) {
      return PlaylistConfig(
        id: playlist.id,
        name: playlist.name,
        dns: playlist.serverUrl,
        username: playlist.username,
        password: playlist.password,
        createdAt: playlist.createdAt,
        isActive: true,
      );
    }
    return null;
  }

  // Create API handlers
  final authHandler = AuthHandler(db);
  final playlistsHandler = PlaylistsHandler(db);
  final usersHandler = UsersHandler(db);
  final settingsHandler = SettingsHandler(db);
  final proxyHandler = ProxyHandler(getPlaylist, db);

  // Setup router
  final apiRouter = Router()
    // Auth endpoints
    ..mount('/api/auth', authHandler.router)
    // Playlists endpoints
    ..mount(
      '/api/playlists',
      const Pipeline()
          .addMiddleware(authMiddleware(db))
          .addHandler(playlistsHandler.router.call),
    )
    // Users endpoints
    ..mount(
      '/api/users',
      const Pipeline()
          .addMiddleware(authMiddleware(db))
          .addHandler(usersHandler.router.call),
    )
    // Settings endpoints
    ..mount(
      '/api/settings',
      const Pipeline()
          .addMiddleware(authMiddleware(db))
          .addHandler(settingsHandler.router.call),
    );
    // NOTE: /api/xtream is handled by proxyHandler in the Cascade below
    // Do NOT mount here as it would intercept and block the actual proxy

  // Initialize Cleanup Service
  final cleanupService = CleanupService();
  cleanupService.addTarget(Directory.systemTemp);
  cleanupService.addTarget(Directory('/app/data/logs'));
  cleanupService.addTarget(Directory('/app/data/tmp'));

  cleanupService.start();

  // Admin Routes (protected)
  apiRouter.mount(
    '/api/admin',
    const Pipeline()
        .addMiddleware(authMiddleware(db))
        .addHandler((Request request) {
      final router = Router();

      // POST /api/admin/purge
      router.post('/purge', (Request req) async {
        final user = req.context['user'] as User?;
        if (user == null || !user.isAdmin) {
          return Response.forbidden(
            jsonEncode({'error': 'Admin access required'}),
          );
        }

        final result = await cleanupService.runCleanup();
        return Response.ok(
          jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      });

      return router(request);
    }),
  );

  // Create static handler
  final baseStaticHandler = createStaticHandler(
    webPath,
    defaultDocument: 'index.html',
    listDirectories: false,
  );

  // Wrap static handler to enforce cache policies
  FutureOr<Response> staticHandler(Request request) async {
    final response = await baseStaticHandler(request);

    // Disable cache for entry points to ensure updates are seen immediately
    final path = request.url.path;
    if (path.isEmpty ||
        path == 'index.html' ||
        path.endsWith('.js') ||
        path.endsWith('.json')) {
      return response.change(
        headers: {
          'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );
    }

    // Allow aggressive caching for hashed assets
    return response.change(
      headers: {
        'Cache-Control': 'public, max-age=86400',
      },
    );
  }

  // Create Streaming Router (Mount handlers on correct paths)
  final streamingRouter = Router()
    ..mount(
      '/api/live',
      createLiveStreamHandler(
        getPlaylist,
        isGpuEnabled: db.isNvidiaGpuEnabled,
      ),
    )
    ..mount(
      '/api/vod',
      createVodStreamHandler(
        getPlaylist,
        isGpuEnabled: db.isNvidiaGpuEnabled,
      ),
    );

  // Proxy Handler (auth is now handled INSIDE the handler, after path check)
  // This allows non-/api/xtream requests to fall through to static handler
  final proxyPipeline = proxyHandler.handler;

  // Main handler
  final handler = Cascade()
      .add(apiRouter.call) /* Standard API endpoints */
      .add(proxyPipeline) /* Xtream Proxy (auth inside handler) */
      .add(streamingRouter.call) /* Streaming endpoints */
      .add(staticHandler)
      .handler;

  // Add middleware
  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(honeypotMiddleware())
      .addMiddleware(rateLimitMiddleware())
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
  print('Xtream proxy available at: /api/xtream/* (SSRF Protected)');

  // Clean expired sessions periodically (every hour)
  Timer.periodic(const Duration(hours: 1), (_) {
    db.cleanExpiredSessions();
    print('Cleaned expired sessions');
  });
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

