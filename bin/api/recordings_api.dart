import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import '../database/database.dart';
import '../models/user.dart';
import '../services/recording_scheduler.dart';
import '../utils/safe_path.dart';

class RecordingsApi {
  final AppDatabase _db;
  final RecordingScheduler _scheduler;

  RecordingsApi(this._db, this._scheduler);

  /// Handler pour GET /api/recordings/logs/<id>
  /// Exposé séparément car shelf_router a un conflit entre DELETE /<id> et GET /logs/<id>
  Future<Response> getLogHandler(Request request, String id) async {
    final recording = _db.getRecordingById(id);
    
    if (recording == null) {
      return Response.notFound(
        json.encode({'error': 'Enregistrement non trouvé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (recording.filePath == null) {
      return Response.notFound(
        json.encode({'error': 'Aucun fichier ni log associé pour le moment.'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Les enregistrements sont écrits en .mkv avec un .log à côté
    // (l'ancien replaceAll('.mp4', '.log') ne trouvait jamais le fichier).
    final logFilePath = p.setExtension(recording.filePath!, '.log');

    // Anti path-traversal : le log doit rester dans /app/recordings
    final safeLogPath = SafePath.resolveWithin('/app/recordings', logFilePath);
    if (safeLogPath == null) {
      return Response.forbidden(
        json.encode({'error': 'Chemin de log invalide'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final logFile = File(safeLogPath);

    if (!await logFile.exists()) {
      return Response.notFound(
        json.encode({'error': 'Le fichier de log est introuvable.'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final logs = await logFile.readAsString();
    return Response.ok(
      json.encode({'logs': logs}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/recordings — Liste les enregistrements de l'utilisateur
  /// (tous les enregistrements pour un admin)
  Response handleGetAll(Request request) {
    final user = request.context['user'] as User?;
    final recordings = (user != null && !user.isAdmin)
        ? _db.getUserRecordings(user.id)
        : _db.getAllRecordings();
    return Response.ok(
      json.encode(recordings.map((r) => r.toMap()).toList()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /api/recordings — Planifie un nouvel enregistrement
  Future<Response> handlePost(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = json.decode(payload);

      final userId = request.context['userId'] as String? ?? 'dev_user_id';
      final recording = _db.createRecording(
        userId: userId,
        channelId: data['channel_id'],
        streamUrl: data['stream_url'],
        title: data['title'] ?? 'Sans Titre',
        startTime: DateTime.parse(data['start_time']),
        endTime: DateTime.parse(data['end_time']),
      );

      return Response.ok(
        recording.toJson(),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur lors de la programmation: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/recordings/<id> — Annule ou supprime un enregistrement
  /// Si un enregistrement FFmpeg est actif, il est arrêté avant la suppression
  Future<Response> handleDelete(Request request, String id) async {
    final recording = _db.getRecordingById(id);

    if (recording == null) {
      return Response.notFound(
        json.encode({'error': 'Enregistrement non trouvé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Tuer FFmpeg si cet enregistrement est en cours AVANT de supprimer de la DB
    await _scheduler.stopRecording(id);

    _db.deleteRecording(id);

    return Response.ok(
      json.encode({'message': 'Enregistrement supprimé avec succès'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /api/recordings/stop/<id> — Arrête un enregistrement FFmpeg en cours
  Future<Response> handleStop(Request request, String id) async {
    final recording = _db.getRecordingById(id);
    if (recording == null) {
      return Response.notFound(
        json.encode({'error': 'Enregistrement non trouvé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final stopped = await _scheduler.stopRecording(id);
    if (stopped) {
      return Response.ok(
        json.encode({'message': 'Enregistrement arrêté'}),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      // Pas de processus FFmpeg actif pour cet ID → marquer comme complété quand même
      _db.updateRecordingStatus(id, 'completed');
      return Response.ok(
        json.encode({'message': 'Enregistrement marqué comme terminé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
