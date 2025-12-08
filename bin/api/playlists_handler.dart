import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class PlaylistsHandler {
  final AppDatabase db;

  PlaylistsHandler(this.db);

  Router get router {
    final router = Router();

    router.get('/', _getPlaylists);
    router.post('/', _createPlaylist);
    router.put('/<id>', _updatePlaylist);
    router.delete('/<id>', _deletePlaylist);

    return router;
  }

  /// GET /api/playlists
  Future<Response> _getPlaylists(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final playlists = db.getPlaylists(userId);

      return Response.ok(jsonEncode({
        'playlists': playlists.map((p) => p.toJson()).toList(),
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/playlists
  Future<Response> _createPlaylist(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final name = payload['name'] as String?;
      final serverUrl = payload['serverUrl'] as String?;
      final username = payload['username'] as String?;
      final password = payload['password'] as String?;
      final dns = payload['dns'] as String?;

      if (name == null || serverUrl == null || username == null || password == null) {
        return Response(400, body: jsonEncode({
          'success': false,
          'error': 'Missing required fields',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final playlist = db.createPlaylist(
        userId: userId,
        name: name,
        serverUrl: serverUrl,
        username: username,
        password: password,
        dns: dns ?? serverUrl,
      );

      return Response.ok(jsonEncode({
        'success': true,
        'playlist': playlist.toJson(),
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /api/playlists/:id
  Future<Response> _updatePlaylist(Request request, String id) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      // Verify playlist belongs to user
      final existing = db.getPlaylistById(id);
      if (existing == null) {
        return Response(404, body: jsonEncode({
          'success': false,
          'error': 'Playlist not found',
        }), headers: {'Content-Type': 'application/json'},);
      }

      if (existing.userId != userId) {
        return Response(403, body: jsonEncode({
          'success': false,
          'error': 'Forbidden',
        }), headers: {'Content-Type': 'application/json'},);
      }

      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final name = payload['name'] as String? ?? existing.name;
      final serverUrl = payload['serverUrl'] as String? ?? existing.serverUrl;
      final username = payload['username'] as String? ?? existing.username;
      final password = payload['password'] as String? ?? existing.password;
      final dns = payload['dns'] as String? ?? existing.dns;

      final playlist = db.updatePlaylist(
        playlistId: id,
        name: name,
        serverUrl: serverUrl,
        username: username,
        password: password,
        dns: dns,
      );

      return Response.ok(jsonEncode({
        'success': true,
        'playlist': playlist.toJson(),
      }), headers: {'Content-Type': 'application/json'},);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/playlists/:id
  Future<Response> _deletePlaylist(Request request, String id) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'error': 'Unauthorized',
        }), headers: {'Content-Type': 'application/json'},);
      }

      // Verify playlist belongs to user
      final existing = db.getPlaylistById(id);
      if (existing == null) {
        return Response(404,body: jsonEncode({
          'success': false,
          'error': 'Playlist not found',
        }), headers: {'Content-Type': 'application/json'},);
      }

      if (existing.userId != userId) {
        return Response(403, body: jsonEncode({
          'success': false,
          'error': 'Forbidden',
        }), headers: {'Content-Type': 'application/json'},);
      }

      db.deletePlaylist(id);

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
}
