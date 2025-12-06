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

      // Verify session
      final session = db.findSessionByToken(token);
      if (session == null) {
        return Response(401, body: 'Invalid or expired session');
      }

      // Add userId to context
      final updatedRequest = request.change(context: {
        ...request.context,
        'userId': session.userId,
      });

      return handler(updatedRequest);
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
