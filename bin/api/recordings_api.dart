import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';
import '../services/recording_scheduler.dart';

class RecordingsApi {
  final AppDatabase _db;
  final RecordingScheduler _scheduler;

  RecordingsApi(this._db, this._scheduler);

  Router get router {
    final router = Router();

    // Récupérer tous les enregistrements (admin) ou les enregistrements de l'utilisateur courant (si filtré plus tard via les middlewares)
    router.get('/', (Request request) {
      // Dans une implémentation complète, nous récupérerions l'ID utilisateur
      // final session = request.context['session'] as Session?;
      // final userId = session?.userId;
      
      final recordings = _db.getAllRecordings();
      return Response.ok(
        json.encode(recordings.map((r) => r.toMap()).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Planifier un nouvel enregistrement
    router.post('/', (Request request) async {
      // final session = request.context['session'] as Session;
      // final userId = session.userId;
      final payload = await request.readAsString();
      final data = json.decode(payload);

      try {
        final recording = _db.createRecording(
          userId: 'dev_user_id', // Remplacer par `userId` dans l'implèm réelle avec Auth
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
          body: json.encode({'error': 'Erreur lors de la programmation de l\'enregistrement : $e'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Supprimer (annuler) un enregistrement
    router.delete('/<id>', (Request request, String id) {
      final recording = _db.getRecordingById(id);
      
      if (recording == null) {
        return Response.notFound(json.encode({'error': 'Enregistrement non trouvé'}));
      }

      // 1. Si l'enregistrement est en cours, il faut potentiellement l'arrêter
      // _scheduler.cancelRecording(id); // Ceci pourrait être une nouvelle méthode de l'ordonnanceur

      // 2. Supprimer la donnée en BDD
      _db.deleteRecording(id);

      // 3. Supprimer le fichier vidéo physiquement si existant
      /*
      if (recording.filePath != null) {
        final file = File(recording.filePath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      */

      return Response.ok(
        json.encode({'message': 'Enregistrement supprimé avec succès'}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router;
  }
}
