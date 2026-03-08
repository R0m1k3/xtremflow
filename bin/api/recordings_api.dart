import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';
import '../services/recording_scheduler.dart';

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

    final logFilePath = recording.filePath!.replaceAll('.mp4', '.log');
    final logFile = File(logFilePath);

    if (!await logFile.exists()) {
      return Response.notFound(
        json.encode({'error': 'Le fichier de log est introuvable. Chemin: $logFilePath'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final logs = await logFile.readAsString();
    return Response.ok(
      json.encode({'logs': logs}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/recordings — Liste tous les enregistrements
  Response handleGetAll(Request request) {
    final recordings = _db.getAllRecordings();
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

      final recording = _db.createRecording(
        userId: 'dev_user_id',
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
  Response handleDelete(Request request, String id) {
    final recording = _db.getRecordingById(id);
    
    if (recording == null) {
      return Response.notFound(
        json.encode({'error': 'Enregistrement non trouvé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    _db.deleteRecording(id);

    return Response.ok(
      json.encode({'message': 'Enregistrement supprimé avec succès'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
