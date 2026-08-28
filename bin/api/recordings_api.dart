import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import '../database/database.dart';
import '../models/recording.dart';
import '../models/user.dart';
import '../services/recording_scheduler.dart';
import '../utils/safe_path.dart';

class RecordingsApi {
  final AppDatabase _db;
  final RecordingScheduler _scheduler;

  /// Durée maximale d'un enregistrement (env MAX_RECORDING_HOURS).
  final int maxRecordingHours = int.tryParse(
        Platform.environment['MAX_RECORDING_HOURS'] ?? '',
      ) ??
      12;

  RecordingsApi(this._db, this._scheduler);

  Response _json(int status, Map<String, dynamic> body) => Response(
        status,
        body: json.encode(body),
        headers: {'Content-Type': 'application/json'},
      );

  /// L'utilisateur courant peut-il agir sur cet enregistrement ?
  /// (même patron de contrôle de propriété que playlists_handler)
  bool _canAccess(User? user, Recording recording) {
    if (user == null) return false;
    return user.isAdmin || recording.userId == user.id;
  }

  /// Handler pour GET /api/recordings/logs/<id>
  /// Exposé séparément car shelf_router a un conflit entre DELETE /<id> et GET /logs/<id>
  Future<Response> getLogHandler(Request request, String id) async {
    final recording = _db.getRecordingById(id);

    if (recording == null) {
      return _json(404, {'error': 'Enregistrement non trouvé'});
    }

    final user = request.context['user'] as User?;
    if (!_canAccess(user, recording)) {
      return _json(403, {'error': 'Accès refusé'});
    }

    if (recording.filePath == null) {
      return _json(404, {'error': 'Aucun fichier ni log associé pour le moment.'});
    }

    // Les enregistrements sont écrits en .mkv avec un .log à côté
    // (l'ancien replaceAll('.mp4', '.log') ne trouvait jamais le fichier).
    final logFilePath = p.setExtension(recording.filePath!, '.log');

    // Anti path-traversal : le log doit rester dans le dossier des enregistrements
    final safeLogPath = SafePath.resolveWithin(recordingsDirPath, logFilePath);
    if (safeLogPath == null) {
      return _json(403, {'error': 'Chemin de log invalide'});
    }

    final logFile = File(safeLogPath);

    if (!await logFile.exists()) {
      return _json(404, {'error': 'Le fichier de log est introuvable.'});
    }

    final logs = await logFile.readAsString();
    return _json(200, {'logs': logs});
  }

  /// GET /api/recordings — Liste les enregistrements de l'utilisateur
  /// (tous les enregistrements pour un admin), enrichis des informations de
  /// suivi : taille du fichier, progression, relances FFmpeg.
  Response handleGetAll(Request request) {
    final user = request.context['user'] as User?;
    final recordings = (user != null && !user.isAdmin)
        ? _db.getUserRecordings(user.id)
        : _db.getAllRecordings();
    final now = DateTime.now().toUtc();
    return Response.ok(
      json.encode(recordings.map((r) => _enrich(r, now)).toList()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Map<String, dynamic> _enrich(Recording r, DateTime now) {
    final map = r.toMap();

    if (r.status == 'recording') {
      final start = r.startTime.toUtc();
      final end = r.endTime.toUtc();
      final total = end.difference(start).inSeconds;
      if (total > 0) {
        final elapsed = now.difference(start).inSeconds;
        map['progress_pct'] =
            (elapsed * 100 / total).clamp(0, 100).round();
      }
      map['is_active'] = _scheduler.isCapturing(r.id);
      final retries = _scheduler.retryCountOf(r.id);
      if (retries != null) map['retry_count'] = retries;
    }

    final path = r.filePath;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) map['file_size_bytes'] = file.lengthSync();
      } catch (_) {}
    }

    return map;
  }

  /// POST /api/recordings — Planifie un nouvel enregistrement
  Future<Response> handlePost(Request request) async {
    final user = request.context['user'] as User?;
    final userId = user?.id ?? request.context['userId'] as String?;
    if (userId == null) {
      return _json(401, {'error': 'Authentification requise'});
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json(400, {'error': 'Corps JSON invalide'});
    }

    final channelId = data['channel_id']?.toString() ?? '';
    final streamUrl = data['stream_url']?.toString() ?? '';
    if (channelId.isEmpty) {
      return _json(400, {'error': 'channel_id est requis'});
    }
    if (streamUrl.isEmpty) {
      return _json(400, {'error': 'stream_url est requis'});
    }

    final startTime = _parseZonedDate(data['start_time']);
    final endTime = _parseZonedDate(data['end_time']);
    if (startTime == null || endTime == null) {
      // Une date sans indicateur de fuseau ('Z' ou ±hh:mm) est ambiguë :
      // l'interpréter dans le fuseau du serveur décale l'enregistrement
      // de plusieurs heures selon le TZ du conteneur.
      return _json(400, {
        'error':
            'start_time et end_time doivent être des dates ISO-8601 avec fuseau '
            '(ex: 2026-08-27T21:00:00Z)',
      });
    }
    if (!endTime.isAfter(startTime)) {
      return _json(400, {'error': 'end_time doit être après start_time'});
    }
    if (endTime.difference(startTime) > Duration(hours: maxRecordingHours)) {
      return _json(400, {
        'error': 'Durée maximale dépassée ($maxRecordingHours h)',
      });
    }

    try {
      final recording = _db.createRecording(
        userId: userId,
        channelId: channelId,
        streamUrl: streamUrl,
        title: data['title']?.toString() ?? 'Sans Titre',
        startTime: startTime,
        endTime: endTime,
      );

      return Response.ok(
        recording.toJson(),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[RecordingsApi] Erreur à la création: $e');
      return _json(500, {'error': 'Erreur lors de la programmation'});
    }
  }

  /// Parse une date ISO-8601 en exigeant un indicateur de fuseau, et la
  /// normalise en UTC. Retourne null si absente, invalide ou naïve.
  DateTime? _parseZonedDate(dynamic raw) {
    final str = raw?.toString() ?? '';
    if (str.isEmpty) return null;
    // 'Z' final ou offset ±hh[:mm] après l'heure
    final hasZone =
        str.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(str);
    if (!hasZone) return null;
    return DateTime.tryParse(str)?.toUtc();
  }

  /// DELETE /api/recordings/<id> — Annule ou supprime un enregistrement
  /// Si un enregistrement FFmpeg est actif, il est arrêté avant la suppression.
  /// Les fichiers associés (.mkv, .log, parties) sont supprimés avec la ligne.
  Future<Response> handleDelete(Request request, String id) async {
    final recording = _db.getRecordingById(id);

    if (recording == null) {
      return _json(404, {'error': 'Enregistrement non trouvé'});
    }

    final user = request.context['user'] as User?;
    if (!_canAccess(user, recording)) {
      return _json(403, {'error': 'Accès refusé'});
    }

    // Tuer FFmpeg si cet enregistrement est en cours AVANT de supprimer de la DB
    await _scheduler.stopRecording(id);

    // Supprimer les fichiers pour ne pas laisser d'orphelins sur le volume,
    // en restant confiné au dossier des enregistrements.
    final path = recording.filePath;
    if (path != null) {
      final safePath = SafePath.resolveWithin(recordingsDirPath, path);
      if (safePath != null) {
        await _scheduler.deleteRecordingFiles(safePath);
      }
    }

    _db.deleteRecording(id);

    return _json(200, {'message': 'Enregistrement supprimé avec succès'});
  }

  /// POST /api/recordings/stop/<id> — Arrête un enregistrement FFmpeg en cours
  Future<Response> handleStop(Request request, String id) async {
    final recording = _db.getRecordingById(id);
    if (recording == null) {
      return _json(404, {'error': 'Enregistrement non trouvé'});
    }

    final user = request.context['user'] as User?;
    if (!_canAccess(user, recording)) {
      return _json(403, {'error': 'Accès refusé'});
    }

    final stopped = await _scheduler.stopRecording(id);
    if (stopped) {
      return _json(200, {'message': 'Enregistrement arrêté'});
    }

    if (recording.status == 'scheduled') {
      // Rien n'a encore été capturé : annulé, pas « terminé ». Marquer
      // completed sans fichier faisait ensuite échouer la lecture.
      _db.updateRecordingStatus(id, 'cancelled');
      return _json(200, {'message': 'Enregistrement annulé'});
    }

    if (recording.status == 'recording') {
      // Statut « recording » sans processus actif (orphelin) : clôturer.
      _db.updateRecordingStatus(id, 'completed');
      return _json(200, {'message': 'Enregistrement marqué comme terminé'});
    }

    // Déjà completed/failed/cancelled : ne pas écraser le statut final.
    return _json(200, {'message': 'Enregistrement déjà clôturé'});
  }
}
