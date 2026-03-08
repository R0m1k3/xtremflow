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
      // Toujours comparer en UTC pour éviter les problèmes de fuseau horaire
      final now = DateTime.now().toUtc();
      
      final recordings = _db.getAllRecordings();
      print('[RecordingScheduler] VÉRIFICATION: now=$now recordings=${recordings.length}');

      // Si un enregistrement est en cours, vérifier s'il doit s'arrêter
      if (_currentRecording != null) {
        if (now.isAfter(_currentRecording!.endTime.toUtc())) {
          print('[RecordingScheduler] Fin de l\'enregistrement : ${_currentRecording!.title}');
          await _stopCurrentRecording();
        }
      }

      // Rechercher les enregistrements planifiés
      for (final recording in recordings) {
         // Nettoyer les enregistrements bloqués "recording" suite à un crash serveur
        if (recording.status == 'recording' && _currentRecording?.id != recording.id) {
            print('[RecordingScheduler] Enregistrement orphelin détecté: ${recording.id}');
            _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Interruption inattendue du serveur');
            continue;
        }

        if (recording.status == 'scheduled') {
          final startUtc = recording.startTime.toUtc();
          final endUtc = recording.endTime.toUtc();
          print('[RecordingScheduler] "${recording.title}" start=$startUtc end=$endUtc now=$now isAfterStart=${now.isAfter(startUtc)} isBeforeEnd=${now.isBefore(endUtc)}');

          // Si l'enregistrement est planifié, qu'il est temps de démarrer et qu'il n'est pas déjà fini
          if (now.isAfter(startUtc) && now.isBefore(endUtc)) {
            if (_currentRecording != null) {
              print('[RecordingScheduler] Conflit: "${recording.title}" ne peut pas démarrer, "${_currentRecording!.title}" est en cours.');
              _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Un autre enregistrement était déjà en cours.');
              continue;
            }
            print('[RecordingScheduler] *** DÉMARRAGE DE L\'ENREGISTREMENT : ${recording.title} ***');
            await _startRecording(recording);
          }
          
          // Si l'enregistrement est planifié mais que la date de fin est dépassée (loupé)
          if (now.isAfter(endUtc)) {
            print('[RecordingScheduler] Enregistrement "${recording.title}" manqué (fin dépassée).');
            _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Heure de fin dépassée avant le démarrage');
          }
        }
      }
    } catch (e, st) {
      print('[RecordingScheduler] ERREUR CRITIQUE: $e\n$st');
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _startRecording(Recording recording) async {
    _currentRecording = recording;
    _db.updateRecordingStatus(recording.id, 'recording');

    // Un seul bloc try/catch englobant TOUT pour éviter les Unhandled exceptions
    // qui tueraient le serveur entier
    try {
      // Préparation du dossier d'enregistrement
      final recordingsDir = Directory('/app/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Nettoyer l'espace disque si nécessaire
      await _checkDiskSpaceAndRotate(recordingsDir);

      // Génération d'un nom de fichier unique et sûr
      final safeTitle = recording.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final dateStr = recording.startTime.toUtc().toIso8601String().replaceAll(':', '').split('.')[0];
      final fileName = '${safeTitle}_$dateStr.mp4';
      final filePath = p.join(recordingsDir.path, fileName);
      final logFilePath = filePath.replaceAll('.mp4', '.log');

      // Résoudre l'URL relative en URL absolue pour FFmpeg
      // Le serveur Xtremflow tourne sur le port 8089 en interne Docker
      String streamUrl = recording.streamUrl;
      if (streamUrl.startsWith('/')) {
        streamUrl = 'http://localhost:8089$streamUrl';
      }

      final args = [
        '-y',
        '-i', streamUrl,
        '-c', 'copy',
        '-t', '${recording.endTime.difference(DateTime.now()).inSeconds}',
        filePath
      ];

      // Créer le fichier de log de façon sécurisée (openWrite peut lancer une exception)
      IOSink? logSink;
      try {
        logSink = File(logFilePath).openWrite();
        logSink.writeln('[${DateTime.now()}] Démarrage: ${recording.title}');
        logSink.writeln('URL: $streamUrl');
        logSink.writeln('Destination: $filePath');
      } catch (logError) {
        // Si on ne peut pas créer le log, on continue quand même (l'enregistrement reste prioritaire)
        print('[RecordingScheduler] AVERTISSEMENT: Impossible de créer le fichier log ($logFilePath): $logError');
        // On note la filePath dans la DB quand même pour pouvoir retourner le statut
        _db.updateRecordingStatus(recording.id, 'recording', filePath: filePath);
      }

      // Trouver ffmpeg
      String ffmpegPath = 'ffmpeg';
      if (Platform.isLinux && await File('/usr/local/bin/ffmpeg').exists()) {
        ffmpegPath = '/usr/local/bin/ffmpeg';
      }

      logSink?.writeln('Commande: $ffmpegPath ${args.join(' ')}\n');
      print('[RecordingScheduler] Exécution: $ffmpegPath ${args.join(' ')}');

      _ffmpegProcess = await Process.start(ffmpegPath, args);

      // Rediriger stdout/stderr dans le log
      _ffmpegProcess!.stdout.listen((event) => logSink?.add(event));
      _ffmpegProcess!.stderr.listen((event) => logSink?.add(event));

      // Enregistrer le chemin du fichier dans la BDD
      _db.updateRecordingStatus(recording.id, 'recording', filePath: filePath);

      // Écouter la fin du processus FFmpeg de manière asynchrone
      _ffmpegProcess!.exitCode.then((exitCode) async {
        if (_currentRecording?.id == recording.id) {
          logSink?.writeln('\n[${DateTime.now()}] FFmpeg terminé avec le code $exitCode');
          await logSink?.close();

          if (exitCode == 0 || exitCode == 255) {
            print('[RecordingScheduler] Enregistrement terminé: ${recording.title}');
            _db.updateRecordingStatus(recording.id, 'completed');
          } else {
            print('[RecordingScheduler] Erreur FFmpeg (code: $exitCode) pour ${recording.title}');
            _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Erreur FFmpeg code $exitCode. Voir logs.');
          }
          _currentRecording = null;
          _ffmpegProcess = null;
        } else {
          await logSink?.close();
        }
      });

    } catch (e, st) {
      // Attraper TOUTES les exceptions pour éviter de crasher le serveur
      print('[RecordingScheduler] ERREUR dans _startRecording: $e\n$st');
      _db.updateRecordingStatus(recording.id, 'failed', errorReason: 'Erreur au lancement: $e');
      _currentRecording = null;
      _ffmpegProcess = null;
    }
  }

  /// Arrêter un enregistrement en cours (appelé depuis l'API)
  Future<bool> stopRecording(String id) async {
    if (_ffmpegProcess != null && _currentRecording?.id == id) {
      print('[RecordingScheduler] Arrêt demandé pour: ${_currentRecording!.title}');
      _ffmpegProcess!.kill(ProcessSignal.sigterm);
      _db.updateRecordingStatus(id, 'completed');
      _ffmpegProcess = null;
      _currentRecording = null;
      return true;
    }
    return false; // Pas d'enregistrement actif avec cet ID
  }

  Future<void> _stopCurrentRecording({String? reason}) async {
    if (_ffmpegProcess != null && _currentRecording != null) {
      print('[RecordingScheduler] Arrêt auto: ${reason ?? "Fin programmée"}');
      _ffmpegProcess!.kill(ProcessSignal.sigterm);
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
