import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class AuthHandler {
  final AppDatabase db;

  AuthHandler(this.db);

  Router get router {
    final router = Router();

    router.post('/login', _login);
    router.post('/logout', _logout);
    router.get('/me', _getCurrentUser);

    return router;
  }

  /// POST /api/auth/login
  Future<Response> _login(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final username = payload['username'] as String?;
      final password = payload['password'] as String?;

      if (username == null || password == null) {
        return Response(400, body: jsonEncode({
          'success': false,
          'error': 'Username and password are required',
        }), headers: {'Content-Type': 'application/json'},);
      }

      // Verify credentials
      final user = db.verifyCredentials(username, password);
      if (user == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Invalid credentials',
        }), headers: {'Content-Type': 'application/json'},);
      }

      // Create session
      final session = db.createSession(user.id);

      return Response.ok(jsonEncode({
        'success': true,
        'user': user.toJson(),
        'token': session.token,
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/auth/logout
  Future<Response> _logout(Request request) async {
    try {
      final token = _extractToken(request);
      if (token == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      db.deleteSession(token);

      return Response.ok(jsonEncode({
        'success': true,
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /api/auth/me
  Future<Response> _getCurrentUser(Request request) async {
    try {
      final token = _extractToken(request);
      if (token == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final session = db.findSessionByToken(token);
      if (session == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Invalid or expired session',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final user = db.findUserById(session.userId);
      if (user == null) {
        return Response(404, body: jsonEncode({
          'success': false,
          'error': 'User not found',
        }), headers: {'Content-Type': 'application/json'},);
      }

      return Response.ok(jsonEncode({
        'user': user.toJson(),
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
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
}
