import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';
import '../models/user.dart';

class SettingsHandler {
  final AppDatabase db;

  SettingsHandler(this.db);

  Router get router {
    final router = Router();

    // GET /api/settings
    router.get('/', (Request req) {
      final user = req.context['user'] as User?;
      if (user == null) {
        return Response.forbidden(jsonEncode({'error': 'Authentication required'}));
      }

      final settingsJson = db.getUserSettings(user.id);
      
      // If no settings exist, return empty object or default
      return Response.ok(
        settingsJson ?? '{}',
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /api/settings
    router.post('/', (Request req) async {
      final user = req.context['user'] as User?;
      if (user == null) {
        return Response.forbidden(jsonEncode({'error': 'Authentication required'}));
      }

      try {
        final body = await req.readAsString();
        // Validate JSON
        try {
          jsonDecode(body);
        } catch (e) {
          return Response.badRequest(body: jsonEncode({'error': 'Invalid JSON'}));
        }

        db.updateUserSettings(user.id, body);

        return Response.ok(
          body,
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to save settings: $e'}),
        );
      }
    });

    return router;
  }
}
