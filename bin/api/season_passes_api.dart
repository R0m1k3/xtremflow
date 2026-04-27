import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../database/database.dart';
import '../models/user.dart';

/// API Season Passes — enregistrements répétés par titre d'émission
class SeasonPassesApi {
  final AppDatabase _db;

  SeasonPassesApi(this._db);

  /// GET /api/season-passes — liste tous les season passes
  Response handleGetAll(Request request) {
    try {
      final passes = _db.getAllSeasonPasses();
      return Response.ok(
        json.encode(passes),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/season-passes — créer un season pass
  Future<Response> handlePost(Request request) async {
    try {
      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;

      final showTitle = data['show_title'] as String?;
      final channelId = data['channel_id'] as String?;
      final streamUrl = data['stream_url'] as String?;

      if (showTitle == null || showTitle.isEmpty) {
        return Response(
          400,
          body: json.encode({'error': 'show_title est requis'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (channelId == null || channelId.isEmpty) {
        return Response(
          400,
          body: json.encode({'error': 'channel_id est requis'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (streamUrl == null || streamUrl.isEmpty) {
        return Response(
          400,
          body: json.encode({'error': 'stream_url est requis'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Récupérer l'utilisateur depuis le contexte
      final user = request.context['user'] as User?;
      final userId = user?.id ?? 'admin'; // fallback

      // Vérifier si un season pass identique existe déjà
      final existing = _db.getAllSeasonPasses();
      final duplicate = existing.any(
        (p) =>
            (p['show_title'] as String).toLowerCase() ==
                showTitle.toLowerCase() &&
            p['channel_id'] == channelId,
      );
      if (duplicate) {
        return Response(
          409,
          body: json.encode({'error': 'Un Season Pass identique existe déjà'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final pass = _db.createSeasonPass(
        userId: userId,
        showTitle: showTitle,
        channelId: channelId,
        streamUrl: streamUrl,
      );

      print('[SeasonPass] Créé: "$showTitle" sur chaîne $channelId');
      return Response(
        201,
        body: json.encode(pass),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/season-passes/<id> — supprimer un season pass
  Response handleDelete(Request request, String id) {
    try {
      _db.deleteSeasonPass(id);
      return Response.ok(
        json.encode({'message': 'Season Pass supprimé'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
