import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../models/recording.dart';
import '../utils/log_redactor.dart';
import 'recording_decision.dart';
import 'package:path/path.dart' as p;

class _ActiveRecording {
  final Recording recording;
  final Process process;
  _ActiveRecording(this.recording, this.process);
}

class RecordingScheduler {
  final AppDatabase _db;
  Timer? _timer;
  Timer? _seasonPassTimer;
  bool _isRunning = false;

  /// Enregistrements actuellement en cours, indexés par id.
  final Map<String, _ActiveRecording> _active = {};

  /// Nombre maximum d'enregistrements simultanés (env MAX_CONCURRENT_RECORDINGS).
  final int maxConcurrent = int.tryParse(
        Platform.environment['MAX_CONCURRENT_RECORDINGS'] ?? '',
      ) ??
      2;

  // Playlist config pour les appels EPG des season passes
  // Rempli depuis server.dart après initialisation
  String? playlistDns;
  String? playlistUsername;
  String? playlistPassword;

  RecordingScheduler(this._db);

  void start() {
    print(
      '[RecordingScheduler] Démarrage du planificateur d\'enregistrements TV '
      '(max simultanés: $maxConcurrent)',
    );
    // Vérifier toutes les 10 secondes (pour un démarrage quasi-immédiat)
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkAndRunRecordings(),
    );
    // Season Passes : vérifier toutes les 4 heures
    _seasonPassTimer =
        Timer.periodic(const Duration(hours: 4), (_) => _checkSeasonPasses());
    // Lancer une première vérification immédiatement
    _checkAndRunRecordings();
    // Vérification initiale des season passes après 30s (laisser le serveur démarrer)
    Timer(const Duration(seconds: 30), _checkSeasonPasses);
  }

  void stop() {
    _timer?.cancel();
    _seasonPassTimer?.cancel();
    for (final id in _active.keys.toList()) {
      _stopActiveRecording(id, reason: 'Arrêt du service planificateur');
    }
    print('[RecordingScheduler] Arrêté');
  }

  Future<void> _checkAndRunRecordings() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      // Toujours comparer en UTC pour éviter les problèmes de fuseau horaire
      final now = DateTime.now().toUtc();

      final recordings = _db.getAllRecordings();

      // Arrêter les enregistrements actifs dont l'heure de fin est passée
      for (final id in _active.keys.toList()) {
        final active = _active[id]!;
        if (now.isAfter(active.recording.endTime.toUtc())) {
          print(
            '[RecordingScheduler] Fin de l\'enregistrement : ${active.recording.title}',
          );
          _stopActiveRecording(id);
        }
      }

      // Rechercher les enregistrements planifiés
      for (final recording in recordings) {
        // Nettoyer les enregistrements bloqués "recording" suite à un crash serveur
        if (recording.status == 'recording' &&
            !_active.containsKey(recording.id)) {
          print(
            '[RecordingScheduler] Enregistrement orphelin détecté: ${recording.id}',
          );
          _db.updateRecordingStatus(
            recording.id,
            'failed',
            errorReason: 'Interruption inattendue du serveur',
          );
          continue;
        }

        if (recording.status == 'scheduled') {
          final action = decideRecordingAction(
            now: now,
            startTime: recording.startTime,
            endTime: recording.endTime,
            activeCount: _active.length,
            maxConcurrent: maxConcurrent,
          );

          switch (action) {
            case RecordingAction.start:
              print(
                '[RecordingScheduler] *** DÉMARRAGE DE L\'ENREGISTREMENT : ${recording.title} ***',
              );
              await _startRecording(recording);
            case RecordingAction.wait:
              // Capacité atteinte mais la fenêtre est encore ouverte :
              // on garde le statut "scheduled" et on réessaiera au prochain tick.
              print(
                '[RecordingScheduler] Capacité max atteinte (${_active.length}/$maxConcurrent), '
                '"${recording.title}" en attente.',
              );
            case RecordingAction.fail:
              print(
                '[RecordingScheduler] Enregistrement "${recording.title}" manqué (fin dépassée).',
              );
              _db.updateRecordingStatus(
                recording.id,
                'failed',
                errorReason: 'Heure de fin dépassée avant le démarrage',
              );
            case RecordingAction.none:
              break;
          }
        }
      }
    } catch (e, st) {
      print('[RecordingScheduler] ERREUR CRITIQUE: $e\n$st');
    } finally {
      _isRunning = false;
    }
  }

  /// Vérifier les Season Passes et créer des enregistrements pour les nouvelles diffusions
  Future<void> _checkSeasonPasses() async {
    final passes = _db.getAllSeasonPasses();
    if (passes.isEmpty) return;

    final dns = playlistDns;
    final username = playlistUsername;
    final password = playlistPassword;

    if (dns == null || username == null || password == null) {
      print(
        '[SeasonPass] Config playlist non disponible, vérification annulée',
      );
      return;
    }

    print('[SeasonPass] Vérification de ${passes.length} Season Pass(s)...');

    for (final pass in passes) {
      try {
        final channelId = pass['channel_id'] as String;
        final streamUrl = pass['stream_url'] as String;
        final showTitle = pass['show_title'] as String;
        final userId = pass['user_id'] as String;

        // Récupérer l'EPG de la chaîne (48 prochaines heures)
        final url = '$dns/player_api.php?username=$username&password=$password'
            '&action=get_simple_data_table&stream_id=$channelId&type=epg&limit=48';

        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) continue;

        final raw = json.decode(response.body);
        final listings =
            (raw is Map ? raw['epg_listings'] : raw) as List<dynamic>? ?? [];

        for (final item in listings) {
          String title = item['title'] as String? ?? '';
          try {
            title = utf8.decode(base64Decode(title));
          } catch (_) {}

          // Vérifier si le titre correspond au Season Pass (insensible casse, recherche partielle)
          if (!title.toLowerCase().contains(showTitle.toLowerCase())) continue;

          // Parser les heures de début/fin
          final startStr = item['start'] as String? ?? '';
          final endStr =
              item['stop'] as String? ?? item['end'] as String? ?? '';
          if (startStr.isEmpty || endStr.isEmpty) continue;

          DateTime startTime, endTime;
          try {
            startTime = DateTime.parse(startStr).toUtc();
            endTime = DateTime.parse(endStr).toUtc();
          } catch (_) {
            continue;
          }

          // Ne pas créer pour les programmes déjà terminés
          if (endTime.isBefore(DateTime.now().toUtc())) continue;

          // Déduplication : vérifier si cet épisode est déjà planifié/enregistré
          if (_db.existsRecordingForEpisode(title, startTime)) {
            print('[SeasonPass] "$title" déjà enregistré, skip.');
            continue;
          }

          // Créer l'enregistrement automatiquement
          _db.createRecording(
            userId: userId,
            channelId: channelId,
            streamUrl: streamUrl,
            title: title,
            startTime: startTime,
            endTime: endTime,
          );
          print(
            '[SeasonPass] ✓ Planifié automatiquement: "$title" le ${startTime.toLocal()}',
          );
        }
      } catch (e) {
        print('[SeasonPass] Erreur pour le pass "${pass['show_title']}": $e');
      }
    }
  }

  Future<void> _startRecording(Recording recording) async {
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
      final safeTitle =
          recording.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final dateStr = recording.startTime
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .split('.')[0];
      final fileName = '${safeTitle}_$dateStr.mkv';
      final filePath = p.join(recordingsDir.path, fileName);
      final logFilePath = filePath.replaceAll('.mkv', '.log');

      // Résoudre l'URL relative en URL absolue pour FFmpeg
      // Le serveur Xtremflow tourne sur le port 8089 en interne Docker
      String streamUrl = recording.streamUrl;
      if (streamUrl.startsWith('/')) {
        streamUrl = 'http://localhost:8089$streamUrl';
      }

      final args = [
        '-y',
        '-i',
        streamUrl,
        '-c',
        'copy',
        '-t',
        '${recording.endTime.difference(recording.startTime).inSeconds}',
        filePath,
      ];

      // Créer le fichier de log de façon sécurisée (openWrite peut lancer une exception)
      // Le contenu du log est exposé via l'API : ne jamais y écrire de credentials.
      IOSink? logSink;
      try {
        logSink = File(logFilePath).openWrite();
        logSink.writeln('[${DateTime.now()}] Démarrage: ${recording.title}');
        logSink.writeln('URL: ${LogRedactor.redactUrl(streamUrl)}');
        logSink.writeln('Destination: $filePath');
      } catch (logError) {
        // Si on ne peut pas créer le log, on continue quand même (l'enregistrement reste prioritaire)
        print(
          '[RecordingScheduler] AVERTISSEMENT: Impossible de créer le fichier log ($logFilePath): $logError',
        );
        // On note la filePath dans la DB quand même pour pouvoir retourner le statut
        _db.updateRecordingStatus(
          recording.id,
          'recording',
          filePath: filePath,
        );
      }

      // Trouver ffmpeg
      String ffmpegPath = 'ffmpeg';
      if (Platform.isLinux && await File('/usr/local/bin/ffmpeg').exists()) {
        ffmpegPath = '/usr/local/bin/ffmpeg';
      }

      final redactedArgs =
          args.map(LogRedactor.redactUrl).join(' ');
      logSink?.writeln('Commande: $ffmpegPath $redactedArgs\n');
      print('[RecordingScheduler] Exécution: $ffmpegPath $redactedArgs');

      final process = await Process.start(ffmpegPath, args);
      _active[recording.id] = _ActiveRecording(recording, process);

      // Rediriger stdout/stderr dans le log
      process.stdout.listen((event) => logSink?.add(event));
      process.stderr.listen((event) => logSink?.add(event));

      // Enregistrer le chemin du fichier dans la BDD
      _db.updateRecordingStatus(recording.id, 'recording', filePath: filePath);

      // Écouter la fin du processus FFmpeg de manière asynchrone
      process.exitCode.then((exitCode) async {
        if (_active.containsKey(recording.id)) {
          logSink?.writeln(
            '\n[${DateTime.now()}] FFmpeg terminé avec le code $exitCode',
          );
          await logSink?.close();

          if (exitCode == 0 || exitCode == 255) {
            print(
              '[RecordingScheduler] Enregistrement terminé: ${recording.title}',
            );
            _db.updateRecordingStatus(recording.id, 'completed');
          } else {
            print(
              '[RecordingScheduler] Erreur FFmpeg (code: $exitCode) pour ${recording.title}',
            );
            _db.updateRecordingStatus(
              recording.id,
              'failed',
              errorReason: 'Erreur FFmpeg code $exitCode. Voir logs.',
            );
          }
          _active.remove(recording.id);
        } else {
          await logSink?.close();
        }
      });
    } catch (e, st) {
      // Attraper TOUTES les exceptions pour éviter de crasher le serveur
      print('[RecordingScheduler] ERREUR dans _startRecording: $e\n$st');
      _db.updateRecordingStatus(
        recording.id,
        'failed',
        errorReason: 'Erreur au lancement: $e',
      );
      _active.remove(recording.id);
    }
  }

  /// Arrêter un enregistrement en cours (appelé depuis l'API)
  Future<bool> stopRecording(String id) async {
    if (_active.containsKey(id)) {
      print(
        '[RecordingScheduler] Arrêt demandé pour: ${_active[id]!.recording.title}',
      );
      _stopActiveRecording(id);
      return true;
    }
    return false; // Pas d'enregistrement actif avec cet ID
  }

  void _stopActiveRecording(String id, {String? reason}) {
    final active = _active.remove(id);
    if (active == null) return;
    if (reason != null) {
      print('[RecordingScheduler] Arrêt: $reason (${active.recording.title})');
    }
    active.process.kill(ProcessSignal.sigterm);
    _db.updateRecordingStatus(id, 'completed');
  }

  Future<void> _checkDiskSpaceAndRotate(Directory dir) async {
    // Cette fonction pourrait invoquer une commande système `df` ou simplement lister les fichiers
    // et supprimer les plus anciens si un quota (ex: max 20 Go) est atteint.
    // Pour l'implémentation initiale, nous pouvons lister et supprimer si plus de X fichiers
    try {
      const maxFiles = 50; // Nombre max d'enregistrements (exemple simpliste)
      final files = dir.listSync().whereType<File>().toList();

      if (files.length > maxFiles) {
        print(
          '[RecordingScheduler] Rotation de l\'espace disque : suppression des anciens enregistrements',
        );
        files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
        ); // Du plus vieux au plus récent

        // Supprimer les plus anciens pour revenir sous la limite
        final filesToDelete = files.take(files.length - maxFiles);
        for (var file in filesToDelete) {
          file.deleteSync();
        }
      }
    } catch (e) {
      print(
        '[RecordingScheduler] Erreur lors de la rotation de l\'espace disque : $e',
      );
    }
  }
}
