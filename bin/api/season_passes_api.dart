import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../database/database.dart';
import '../models/user.dart';

/// API Season Passes — enregistrements répétés par titre d'émission
class SeasonPassesApi {
  final AppDatabase _db;

  SeasonPassesApi(this._db);

  /// GET /api/season-passes — liste les season passes de l'utilisateur
  /// (tous les passes pour un admin)
  Response handleGetAll(Request request) {
    try {
      final user = request.context['user'] as User?;
      if (user == null) {
        return Response(
          401,
          body: json.encode({'error': 'Authentification requise'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final passes = user.isAdmin
          ? _db.getAllSeasonPasses()
          : _db.getSeasonPassesForUser(user.id);
      return Response.ok(
        json.encode(passes),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SeasonPass] Erreur au listage: $e');
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur interne'}),
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
      if (user == null) {
        return Response(
          401,
          body: json.encode({'error': 'Authentification requise'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 'exact' par défaut : « Journal » ne doit pas capturer tous les
      // programmes qui contiennent le mot. 'contains' reste disponible.
      final matchMode = data['match_mode'] == 'contains' ? 'contains' : 'exact';

      // Vérifier si un season pass identique existe déjà pour cet utilisateur
      final existing = _db.getSeasonPassesForUser(user.id);
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
        userId: user.id,
        showTitle: showTitle,
        channelId: channelId,
        streamUrl: streamUrl,
        matchMode: matchMode,
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
      final user = request.context['user'] as User?;
      final pass = _db.getSeasonPassById(id);
      if (pass == null) {
        return Response.notFound(
          json.encode({'error': 'Season Pass non trouvé'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      // Contrôle de propriété : seul le propriétaire ou un admin supprime.
      if (user == null || (!user.isAdmin && pass['user_id'] != user.id)) {
        return Response.forbidden(
          json.encode({'error': 'Accès refusé'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      _db.deleteSeasonPass(id);
      return Response.ok(
        json.encode({'message': 'Season Pass supprimé'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SeasonPass] Erreur à la suppression: $e');
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur interne'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
