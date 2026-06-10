import 'dart:io';
import 'package:shelf/shelf.dart';
import '../database/database.dart';

/// Middleware to authenticate requests
Middleware authMiddleware(AppDatabase db) {
  return (Handler handler) {
    return (Request request) async {
      // Skip auth for login endpoint
      if (request.url.path.startsWith('api/auth/login')) {
        return handler(request);
      }

      // Extract token
      final token = _extractToken(request);
      if (token == null) {
        return Response(401, body: 'Unauthorized');
      }

      // Verify session (findSessionByToken enforces expires_at)
      final session = db.findSessionByToken(token);
      if (session == null) {
        return Response(401, body: 'Invalid or expired session');
      }

      // Add user info to context. Both keys are populated because handlers
      // are inconsistent: playlists_handler reads 'userId', while
      // getPlaylist/admin routes read 'user'.
      final user = db.findUserById(session.userId);
      final updatedRequest = request.change(context: {
        ...request.context,
        'userId': session.userId,
        if (user != null) 'user': user,
      },);

      return handler(updatedRequest);
    };
  };
}

/// Auth middleware for streaming routes (HLS playlists/segments).
///
/// hls.js/mpegts.js inside the player iframe cannot send Authorization
/// headers, so these routes accept the HttpOnly session cookie instead.
/// Loopback requests without X-Forwarded-For are allowed through because
/// the recording scheduler's local FFmpeg fetches
/// `http://localhost:8089/api/live/<id>.ts` without credentials.
Middleware streamAuthMiddleware(AppDatabase db) {
  return (Handler handler) {
    return (Request request) async {
      final connectionInfo =
          request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final isLoopback = connectionInfo?.remoteAddress.isLoopback ?? false;
      final viaProxy = request.headers.containsKey('x-forwarded-for');
      if (isLoopback && !viaProxy) {
        return handler(request);
      }

      final token = _extractToken(request);
      if (token == null || db.findSessionByToken(token) == null) {
        return Response(401, body: 'Unauthorized');
      }
      return handler(request);
    };
  };
}

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
