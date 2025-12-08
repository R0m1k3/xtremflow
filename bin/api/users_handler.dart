import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class UsersHandler {
  final AppDatabase db;

  UsersHandler(this.db);

  Router get router {
    final router = Router();
    router.get('/', _getAllUsers);
    router.post('/', _createUser);
    router.put('/<id>/password', _updatePassword);
    router.put('/<id>', _updateUser);
    router.delete('/<id>', _deleteUser);
    return router;
  }

  /// Check if requester is admin
  bool _isAdmin(Request request) {
    final userId = request.context['userId'] as String?;
    if (userId == null) return false;
    final user = db.findUserById(userId);
    return user?.isAdmin ?? false;
  }

  /// GET /api/users
  Future<Response> _getAllUsers(Request request) async {
    try {
      if (!_isAdmin(request)) {
        return Response.forbidden(jsonEncode({'success': false, 'error': 'Admin required'}));
      }

      final users = db.getAllUsers();
      return Response.ok(jsonEncode({
        'success': true,
        'users': users.map((u) => u.toJson()).toList(),
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/users
  Future<Response> _createUser(Request request) async {
    try {
      if (!_isAdmin(request)) {
        return Response.forbidden(jsonEncode({'success': false, 'error': 'Admin required'}));
      }

      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final username = payload['username'] as String?;
      final password = payload['password'] as String?;
      final isAdmin = payload['isAdmin'] as bool? ?? false;

      if (username == null || password == null) {
        return Response.badRequest(body: jsonEncode({
          'success': false,
          'error': 'Missing required fields',
        }), headers: {'Content-Type': 'application/json'},);
      }

      if (db.findUserByUsername(username) != null) {
         return Response.badRequest(body: jsonEncode({
          'success': false,
          'error': 'Username already exists',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final user = db.createUser(username, password, isAdmin: isAdmin);
      return Response.ok(jsonEncode({
        'success': true,
        'user': user.toJson(),
      }), headers: {'Content-Type': 'application/json'},);

    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /api/users/:id/password
  Future<Response> _updatePassword(Request request, String id) async {
    try {
      if (!_isAdmin(request)) {
        return Response.forbidden(jsonEncode({'success': false, 'error': 'Admin required'}));
      }

      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final password = payload['password'] as String?;

      if (password == null) {
        return Response.badRequest(body: jsonEncode({
          'success': false,
          'error': 'Missing password',
        }), headers: {'Content-Type': 'application/json'},);
      }

      db.updateUserPassword(id, password);
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});

    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /api/users/:id (Toggle Admin)
  Future<Response> _updateUser(Request request, String id) async {
    try {
      if (!_isAdmin(request)) {
         return Response.forbidden(jsonEncode({'success': false, 'error': 'Admin required'}));
      }

      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final isAdmin = payload['isAdmin'] as bool?;

      if (isAdmin != null) {
        db.updateUserAdminStatus(id, isAdmin);
      }

      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});

    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/users/:id
  Future<Response> _deleteUser(Request request, String id) async {
     try {
       if (!_isAdmin(request)) {
         return Response.forbidden(jsonEncode({'success': false, 'error': 'Admin required'}));
       }
       
       // Prevent deleting self
       final currentUserId = request.context['userId'] as String;
       if (currentUserId == id) {
          return Response.badRequest(body: jsonEncode({
            'success': false,
            'error': 'Cannot delete yourself',
          }), headers: {'Content-Type': 'application/json'},);
       }

       db.deleteUser(id);
       return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
     } catch (e) {
       return Response.internalServerError(
         body: jsonEncode({'success': false, 'error': e.toString()}),
         headers: {'Content-Type': 'application/json'},
       );
     }
  }
}
