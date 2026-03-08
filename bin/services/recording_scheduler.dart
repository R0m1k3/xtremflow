import 'dart:async';
import 'dart:io';
import '../database/database.dart';
import '../models/recording.dart';
import 'package:path/path.dart' as p;

class RecordingScheduler {
  final AppDatabase _db;
  Timer? _timer;
  bool _isRunning = false;

  // Stocker l'enregistrement actuellement en cours d'exécution
  Recording? _currentRecording;
  Process? _ffmpegProcess;

  RecordingScheduler(this._db);

  void start() {
    print('[RecordingScheduler] Démarrage du planificateur d\'enregistrements TV');
    // Vérifier toutes les 10 secondes (pour un démarrage quasi-immédiat)
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkAndRunRecordings());
    // Lancer une première vérification immédiatement
    _checkAndRunRecordings();
  }

  void stop() {
    _timer?.cancel();
    _stopCurrentRecording(reason: 'Arrêt du service planificateur');
    print('[RecordingScheduler] Arrêté');
  }

  Future<void> _checkAndRunRecordings() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      final now = DateTime.now();
      
      // Si un enregistrement est en cours, vérifier s'il doit s'arrêter
      if (_currentRecording != null) {
        if (now.isAfter(_currentRecording!.endTime)) {
          print('[RecordingScheduler] Fin de l\'enregistrement : ${_currentRecording!.title}');
          await _stopCurrentRecording();
        }
      }

      // Rechercher les enregistrements planifiés
      final recordings = _db.getAllRecordings();
      
      for (final recording in recordings) {
         // Nettoyer les enregistrements bloqués "recording" suite à un crash serveur
        if (recording.status == 'recording' && _currentRecording?.id != recording.id) {
            print('[RecordingScheduler] Correction d\'un enregistrement orphelin (état "recording" sans processus)');
            _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Interruption inattendue du serveur');
            continue;
        }

        // Si l'enregistrement est planifié, qu'il est temps de démarrer et qu'il n'est pas déjà fini
        if (recording.status == 'scheduled' && now.isAfter(recording.startTime) && now.isBefore(recording.endTime)) {
          
          if (_currentRecording != null) {
            print('[RecordingScheduler] Impossible de démarrer "${recording.title}", un autre enregistrement est en cours (${_currentRecording!.title}).');
            _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Un autre enregistrement était déjà en cours (limite de 1 flux simultané).');
            continue;
          }

          print('[RecordingScheduler] Démarrage de l\'enregistrement : ${recording.title}');
          await _startRecording(recording);
        }
        
        // Si l'enregistrement est planifié mais que la date de fin est dépassée (loupé)
        if (recording.status == 'scheduled' && now.isAfter(recording.endTime)) {
           _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Heure de fin dépassée avant le démarrage');
        }
      }
    } catch (e) {
      print('[RecordingScheduler] Erreur lors de la vérification : $e');
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _startRecording(Recording recording) async {
    _currentRecording = recording;
    _db.updateRecordingStatus(recording.id, 'recording');

    try {
      // Préparation du dossier d'enregistrement
      final recordingsDir = Directory('/app/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Nettoyer l'espace disque si nécessaire (TODO : Implémenter logique de roulement ici)
      await _checkDiskSpaceAndRotate(recordingsDir);

      // Génération d'un nom de fichier unique et sûr
      final safeTitle = recording.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final dateStr = recording.startTime.toIso8601String().replaceAll(':', '').split('.')[0];
      final fileName = '${safeTitle}_$dateStr.mp4';
      final filePath = p.join(recordingsDir.path, fileName);

      // FFmpeg arguments pour enregistrement direct (copie sans transcodage = bien plus rapide)
      // On résout l'URL relative en URL absolue pour que FFmpeg puisse y accéder depuis Docker
      String streamUrl = recording.streamUrl;
      if (streamUrl.startsWith('/')) {
        // URL relative → URL absolue (le serveur Xtremflow tourne sur le port 8080 en interne)
        streamUrl = 'http://localhost:8080$streamUrl';
      }
      
      final args = [
        '-y', // Force overwrite
        '-i', streamUrl, // Input stream (URL absolue)
        '-c', 'copy', // Copie directe sans transcodage (beaucoup plus rapide et fiable)
        // Arrêter automatiquement après la durée
        '-t', '${recording.endTime.difference(DateTime.now()).inSeconds}', 
        filePath
      ];

      // Création immédiate du fichier de log pour capturer TOUTES les erreurs
      final logFilePath = filePath.replaceAll('.mp4', '.log');
      final logFile = File(logFilePath);
      final logSink = logFile.openWrite();
      
      logSink.writeln('[${DateTime.now()}] Démarrage de l\'enregistrement : ${recording.title}');
      logSink.writeln('URL source: ${recording.streamUrl}');
      logSink.writeln('Fichier destination: $filePath');
      
      try {
        // En Docker, ffmpeg a été installé dans /usr/local/bin/ffmpeg
        // On teste d'abord s'il existe à cet endroit, sinon on utilise le nom court (pour dev local)
        String ffmpegPath = 'ffmpeg';
        if (Platform.isLinux && await File('/usr/local/bin/ffmpeg').exists()) {
          ffmpegPath = '/usr/local/bin/ffmpeg';
        }

        logSink.writeln('Commande: $ffmpegPath ${args.join(' ')}\n');
        print('[RecordingScheduler] Exécution: $ffmpegPath ${args.join(' ')}');
        
        _ffmpegProcess = await Process.start(ffmpegPath, args);

        // Rediriger la sortie de ffmpeg vers ce fichier
        _ffmpegProcess!.stdout.listen((event) {
          logSink.add(event);
        });
        _ffmpegProcess!.stderr.listen((event) {
          logSink.add(event); // FFmpeg écrit sa progression et ses erreurs ici
        });

        // Enregistrer le chemin du fichier dans la BDD (et donc marquer le log comme disponible)
        _db.updateRecordingStatus(recording.id, 'recording', filePath: filePath);

        // Écouter de manière asynchrone la fin du processus FFmpeg
        _ffmpegProcess!.exitCode.then((exitCode) async {
          if (_currentRecording?.id == recording.id) {
            logSink.writeln('\n[${DateTime.now()}] Processus FFmpeg terminé avec le code $exitCode');
            await logSink.close();

            if (exitCode == 0 || exitCode == 255) { // 255 est souvent renvoyé lors d'un arrêt forcé
               print('[RecordingScheduler] Enregistrement terminé avec succès (${recording.title})');
               _db.updateRecordingStatus(recording.id, 'completed');
            } else {
               print('[RecordingScheduler] Erreur FFmpeg (code: $exitCode) pour l\'enregistrement ${recording.title}');
               _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Erreur FFmpeg code $exitCode. Voir logs.');
            }
            _currentRecording = null;
            _ffmpegProcess = null;
          } else {
            await logSink.close();
          }
        });

      } catch (e) {
        logSink.writeln('\n[${DateTime.now()}] ERREUR CRITIQUE AU LANCEMENT: $e');
        await logSink.close();
        
        print('[RecordingScheduler] Impossible de démarrer FFmpeg: $e');
        _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Impossible de lancer FFmpeg: $e', filePath: filePath);
        _currentRecording = null;
        _ffmpegProcess = null;
      }
      
    } catch (e) {
      print('[RecordingScheduler] Erreur inattendue avant lancement: $e');
      _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Erreur inattendue: $e');
      _currentRecording = null;
      _ffmpegProcess = null;
    }
  }

  Future<void> _stopCurrentRecording({String? reason}) async {
    if (_ffmpegProcess != null && _currentRecording != null) {
      print('[RecordingScheduler] Arrêt forcé du processus FFmpeg. Raison: ${reason ?? "Fin programmée"}');
      _ffmpegProcess!.kill(ProcessSignal.sigterm); // Envoyer un signal d'arrêt propre
      _db.updateRecordingStatus(_currentRecording!.id, 'completed');
      _ffmpegProcess = null;
      _currentRecording = null;
    }
  }

  Future<void> _checkDiskSpaceAndRotate(Directory dir) async {
    // Cette fonction pourrait invoquer une commande système `df` ou simplement lister les fichiers 
    // et supprimer les plus anciens si un quota (ex: max 20 Go) est atteint.
    // Pour l'implémentation initiale, nous pouvons lister et supprimer si plus de X fichiers
    try {
      final maxFiles = 50; // Nombre max d'enregistrements (exemple simpliste)
      final files = dir.listSync().whereType<File>().toList();
      
      if (files.length > maxFiles) {
        print('[RecordingScheduler] Rotation de l\'espace disque : suppression des anciens enregistrements');
        files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified)); // Du plus vieux au plus récent
        
        // Supprimer les plus anciens pour revenir sous la limite
        final filesToDelete = files.take(files.length - maxFiles);
        for (var file in filesToDelete) {
           file.deleteSync();
        }
      }
    } catch (e) {
       print('[RecordingScheduler] Erreur lors de la rotation de l\'espace disque : $e');
    }
  }
}
