import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../models/recording.dart';
import '../utils/log_redactor.dart';
import 'recording_decision.dart';
import 'package:path/path.dart' as p;

/// Dossier où sont écrits les enregistrements et leurs logs.
final String recordingsDirPath =
    Platform.environment['RECORDINGS_DIR'] ?? '/app/recordings';

/// Binaire FFmpeg utilisé pour la capture et la fusion des parties.
Future<String> resolveFfmpegPath() async {
  final fromEnv = Platform.environment['FFMPEG_PATH'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  if (Platform.isLinux && await File('/usr/local/bin/ffmpeg').exists()) {
    return '/usr/local/bin/ffmpeg';
  }
  return 'ffmpeg'; // Depuis le PATH
}

/// Écrivain de log tolérant aux fermetures.
///
/// FFmpeg continue de livrer des morceaux de `stderr` après la résolution de
/// `exitCode` : écrire sur un `IOSink` déjà fermé lève une `StateError` depuis
/// un callback de stream, c'est-à-dire une erreur asynchrone non rattrapée qui
/// tue l'isolate — et donc le serveur entier, laissant l'enregistrement en
/// cours au statut « recording » (« Interruption inattendue du serveur »).
class _RecordingLog {
  final IOSink _sink;
  bool _closed = false;

  _RecordingLog(this._sink) {
    // Une erreur d'écriture disque ne doit pas non plus remonter en erreur
    // asynchrone non rattrapée.
    _sink.done.catchError((_) {});
  }

  /// Ouvre le log, ou renvoie `null` si le fichier n'est pas créable :
  /// l'enregistrement reste prioritaire sur sa journalisation.
  static _RecordingLog? open(String path, {bool append = false}) {
    try {
      return _RecordingLog(
        File(path).openWrite(mode: append ? FileMode.append : FileMode.write),
      );
    } catch (e) {
      print(
        '[RecordingScheduler] AVERTISSEMENT: log indisponible ($path): $e',
      );
      return null;
    }
  }

  void writeln([String line = '']) => _guard(() => _sink.writeln(line));

  void add(List<int> data) => _guard(() => _sink.add(data));

  void _guard(void Function() action) {
    if (_closed) return;
    try {
      action();
    } catch (_) {
      // Sink cassé : on arrête d'écrire plutôt que de propager.
      _closed = true;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.close();
    } catch (_) {}
  }
}

class _ActiveRecording {
  final Recording recording;

  /// Fichier principal (celui exposé par l'API).
  final String filePath;

  final _RecordingLog? log;

  /// Fichiers additionnels écrits après une relance, dans l'ordre.
  final List<String> extraParts;

  /// Index du lancement FFmpeg en cours (0 = fichier principal).
  int attempt;

  /// Échecs consécutifs de FFmpeg, remis à zéro dès qu'une capture tient
  /// assez longtemps pour être considérée saine.
  int consecutiveFailures = 0;

  /// Heure du dernier lancement de FFmpeg.
  DateTime launchedAt = DateTime.now();

  Process? process;

  /// Arrêt volontaire : la sortie de FFmpeg ne doit pas déclencher de relance.
  bool stopping = false;

  _ActiveRecording({
    required this.recording,
    required this.filePath,
    required this.log,
    this.attempt = 0,
    List<String>? extraParts,
  }) : extraParts = extraParts ?? <String>[];
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

      // Lire la base APRÈS les arrêts : un instantané pris avant ferait passer
      // l'enregistrement tout juste terminé pour un orphelin (il n'est plus
      // dans `_active` alors que l'instantané le dit encore « recording »).
      final recordings = _db.getAllRecordings();

      // Rechercher les enregistrements planifiés
      for (final recording in recordings) {
        // Enregistrement marqué "recording" sans processus associé : le serveur
        // a redémarré (ou l'enregistrement n'a jamais démarré).
        if (recording.status == 'recording' &&
            !_active.containsKey(recording.id)) {
          await _recoverOrphan(recording, now);
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

  /// Reprend (ou clôture) un enregistrement laissé au statut "recording" par
  /// une interruption du serveur.
  Future<void> _recoverOrphan(Recording recording, DateTime now) async {
    // Le statut a pu changer depuis la lecture (clôture asynchrone en cours) :
    // ne jamais requalifier un enregistrement sur une donnée périmée.
    final current = _db.getRecordingById(recording.id);
    if (current == null || current.status != 'recording') return;

    final action = decideOrphanAction(
      now: now,
      endTime: current.endTime,
      hasFile: _fileHasData(current.filePath),
    );

    switch (action) {
      case OrphanAction.resume:
        if (_active.length >= maxConcurrent) {
          // Pas de slot libre pour l'instant : on retentera au prochain tick.
          return;
        }
        print(
          '[RecordingScheduler] Reprise après interruption : ${current.title}',
        );
        await _startRecording(current, resume: true);
      case OrphanAction.finish:
        print(
          '[RecordingScheduler] Enregistrement interrompu conservé (partiel): ${current.title}',
        );
        _db.updateRecordingStatus(
          current.id,
          'completed',
          errorReason:
              'Interruption du serveur pendant la capture : fichier partiel',
        );
      case OrphanAction.fail:
        print(
          '[RecordingScheduler] Enregistrement orphelin sans fichier: ${current.id}',
        );
        _db.updateRecordingStatus(
          current.id,
          'failed',
          errorReason: 'Interruption inattendue du serveur',
        );
    }
  }

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

  Future<void> _startRecording(
    Recording recording, {
    bool resume = false,
  }) async {
    // Un (re)démarrage rend obsolète un éventuel motif d'échec précédent.
    _db.updateRecordingStatus(recording.id, 'recording', clearError: true);

    // Un seul bloc try/catch englobant TOUT pour éviter les Unhandled exceptions
    // qui tueraient le serveur entier
    try {
      // Préparation du dossier d'enregistrement
      final recordingsDir = Directory(recordingsDirPath);
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Nettoyer l'espace disque si nécessaire
      await _checkDiskSpaceAndRotate(recordingsDir);

      final filePath = p.join(recordingsDir.path, _fileNameFor(recording));
      final logPath = p.setExtension(filePath, '.log');

      final active = _ActiveRecording(
        recording: recording,
        filePath: filePath,
        // Une reprise complète le log existant au lieu de l'écraser.
        log: _RecordingLog.open(logPath, append: resume),
      );

      if (resume) {
        // Le fichier principal (et d'éventuelles parties) survivent au
        // redémarrage : on repart sur une nouvelle partie pour ne rien écraser.
        active.extraParts.addAll(_existingParts(filePath));
        active.attempt = _fileHasData(filePath) || active.extraParts.isNotEmpty
            ? active.extraParts.length + 1
            : 0;
        active.log?.writeln(
          '\n[${DateTime.now()}] Reprise après interruption du serveur',
        );
      } else {
        active.log?.writeln('[${DateTime.now()}] Démarrage: ${recording.title}');
        active.log?.writeln('Destination: $filePath');
      }

      _active[recording.id] = active;

      // Enregistrer le chemin du fichier dans la BDD
      _db.updateRecordingStatus(recording.id, 'recording', filePath: filePath);

      await _launchFfmpeg(active);
    } catch (e, st) {
      // Attraper TOUTES les exceptions pour éviter de crasher le serveur
      print('[RecordingScheduler] ERREUR dans _startRecording: $e\n$st');
      _db.updateRecordingStatus(
        recording.id,
        'failed',
        errorReason: 'Erreur au lancement: $e',
      );
      final active = _active.remove(recording.id);
      unawaited(active?.log?.close() ?? Future<void>.value());
    }
  }

  /// Lance (ou relance) le processus FFmpeg d'un enregistrement actif.
  Future<void> _launchFfmpeg(_ActiveRecording active) async {
    final recording = active.recording;
    final output = active.attempt == 0
        ? active.filePath
        : _partPath(active.filePath, active.attempt);
    if (active.attempt > 0 && !active.extraParts.contains(output)) {
      active.extraParts.add(output);
    }

    // Résoudre l'URL relative en URL absolue pour FFmpeg
    // Le serveur Xtremflow tourne sur le port 8089 en interne Docker
    String streamUrl = recording.streamUrl;
    if (streamUrl.startsWith('/')) {
      streamUrl = 'http://localhost:8089$streamUrl';
    }

    final duration = captureDuration(
      now: DateTime.now().toUtc(),
      endTime: recording.endTime.toUtc(),
    );

    final args = [
      '-hide_banner',
      // Les logs sont relus entièrement par l'API : sans -nostats, une heure de
      // capture produit des mégaoctets de lignes de progression.
      '-nostats',
      '-user_agent', 'VLC/3.0.18 LibVLC/3.0.18',
      // Une coupure amont (bascule de source, recyclage nginx du panneau) ne
      // doit pas terminer la capture : FFmpeg rouvre le flux lui-même.
      '-reconnect', '1',
      '-reconnect_at_eof', '1',
      '-reconnect_streamed', '1',
      '-reconnect_delay_max', '30',
      '-rw_timeout', '30000000',
      '-y',
      '-i', streamUrl,
      '-c', 'copy',
      '-t', '${duration.inSeconds}',
      output,
    ];

    final ffmpegPath = await resolveFfmpegPath();

    // Le contenu du log est exposé via l'API : ne jamais y écrire de credentials.
    final redactedArgs = args.map(LogRedactor.redactUrl).join(' ');
    active.log?.writeln('URL: ${LogRedactor.redactUrl(streamUrl)}');
    active.log?.writeln('Commande: $ffmpegPath $redactedArgs\n');
    print('[RecordingScheduler] Exécution: $ffmpegPath $redactedArgs');

    final process = await Process.start(ffmpegPath, args);
    active.process = process;
    active.launchedAt = DateTime.now();

    // Rediriger stdout/stderr dans le log ; on attend la fin des deux flux
    // avant de fermer le sink, sinon les derniers morceaux arrivent sur un
    // fichier déjà fermé.
    final drained = Future.wait([
      _pipeToLog(process.stdout, active.log),
      _pipeToLog(process.stderr, active.log),
    ]);

    unawaited(
      process.exitCode.then((exitCode) async {
        await drained;
        await _onFfmpegExit(active, exitCode);
      }).catchError((Object e, StackTrace st) {
        print('[RecordingScheduler] ERREUR à la sortie de FFmpeg: $e\n$st');
      }),
    );
  }

  Future<void> _pipeToLog(Stream<List<int>> stream, _RecordingLog? log) {
    return stream.forEach((chunk) => log?.add(chunk)).catchError((_) {});
  }

  /// Décide de la suite quand un processus FFmpeg se termine.
  Future<void> _onFfmpegExit(_ActiveRecording active, int exitCode) async {
    final recording = active.recording;

    // Arrêt volontaire, ou enregistrement déjà repris ailleurs : la clôture est
    // gérée par celui qui a demandé l'arrêt.
    if (active.stopping || !identical(_active[recording.id], active)) return;

    // Une capture qui a tenu longtemps repart d'un quota de relances neuf.
    final lasted = DateTime.now().difference(active.launchedAt);
    if (lasted > const Duration(minutes: 2) && _activeHasData(active)) {
      active.consecutiveFailures = 0;
    }

    final action = decidePostExitAction(
      now: DateTime.now().toUtc(),
      endTime: recording.endTime.toUtc(),
      exitCode: exitCode,
      consecutiveFailures: active.consecutiveFailures,
      hasFile: _activeHasData(active),
    );

    switch (action) {
      case PostExitAction.retry:
        active.attempt++;
        active.consecutiveFailures++;
        final delay = ffmpegRetryDelay(active.consecutiveFailures);
        final message =
            'FFmpeg s\'est arrêté (code $exitCode) après ${lasted.inSeconds}s, '
            'avant la fin prévue — relance dans ${delay.inSeconds}s '
            '(tentative ${active.consecutiveFailures}/${maxFfmpegAttempts - 1})';
        print('[RecordingScheduler] ${recording.title}: $message');
        active.log?.writeln('\n[${DateTime.now()}] $message');
        // Laisser la source respirer : sur les comptes limités en connexions
        // simultanées, rouvrir immédiatement se fait refuser.
        await Future<void>.delayed(delay);
        if (active.stopping || !identical(_active[recording.id], active)) {
          return;
        }
        try {
          await _launchFfmpeg(active);
        } catch (e) {
          print('[RecordingScheduler] Relance impossible: $e');
          _active.remove(recording.id);
          await _finalize(
            active,
            status: 'failed',
            errorReason: 'Relance de FFmpeg impossible: $e',
          );
        }
      case PostExitAction.complete:
        print(
          '[RecordingScheduler] Enregistrement terminé: ${recording.title}',
        );
        _active.remove(recording.id);
        await _finalize(active, status: 'completed');
      case PostExitAction.fail:
        print(
          '[RecordingScheduler] Erreur FFmpeg (code: $exitCode) pour ${recording.title}',
        );
        _active.remove(recording.id);
        await _finalize(
          active,
          status: 'failed',
          errorReason: 'Erreur FFmpeg code $exitCode. Voir logs.',
        );
    }
  }

  /// Clôture un enregistrement : fusion des parties, fermeture du log, statut.
  Future<void> _finalize(
    _ActiveRecording active, {
    required String status,
    String? errorReason,
  }) async {
    try {
      await _mergeParts(active);
    } catch (e) {
      print('[RecordingScheduler] Fusion des parties impossible: $e');
    }
    active.log?.writeln(
      '\n[${DateTime.now()}] Enregistrement clôturé avec le statut "$status"',
    );
    await active.log?.close();
    _db.updateRecordingStatus(
      active.recording.id,
      status,
      filePath: active.filePath,
      errorReason: errorReason,
    );
  }

  /// Recolle les parties issues des relances dans le fichier principal.
  ///
  /// Les parties proviennent de la même source avec `-c copy` : le demuxer
  /// `concat` de FFmpeg les rassemble sans réencodage. En cas d'échec, le
  /// fichier principal et les parties sont conservés tels quels.
  Future<void> _mergeParts(_ActiveRecording active) async {
    final parts = active.extraParts.where(_fileHasData).toList();
    if (parts.isEmpty) return;

    final segments = [
      if (_fileHasData(active.filePath)) active.filePath,
      ...parts,
    ];
    if (segments.length < 2) {
      // Le fichier principal est vide : la première partie le remplace.
      await File(segments.first).rename(active.filePath);
      return;
    }

    final listFile = File('${active.filePath}.parts.txt');
    await listFile.writeAsString(
      segments.map((s) => 'file \'${s.replaceAll("'", r"'\''")}\'').join('\n'),
    );
    final mergedPath = '${active.filePath}.merged.mkv';
    final ffmpegPath = await resolveFfmpegPath();

    active.log?.writeln(
      '\n[${DateTime.now()}] Fusion de ${segments.length} parties…',
    );
    final result = await Process.run(ffmpegPath, [
      '-hide_banner',
      '-nostats',
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listFile.path,
      '-c', 'copy',
      mergedPath,
    ]);
    await _deleteQuietly(listFile.path);

    if (result.exitCode != 0 || !_fileHasData(mergedPath)) {
      active.log?.writeln(
        'Fusion échouée (code ${result.exitCode}) : les parties sont '
        'conservées séparément.',
      );
      await _deleteQuietly(mergedPath);
      return;
    }

    await File(mergedPath).rename(active.filePath);
    for (final part in parts) {
      await _deleteQuietly(part);
    }
    active.log?.writeln('Fusion terminée.');
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
    active.stopping = true;
    if (reason != null) {
      print('[RecordingScheduler] Arrêt: $reason (${active.recording.title})');
    }
    active.log?.writeln(
      '\n[${DateTime.now()}] Arrêt: ${reason ?? 'fin de la fenêtre programmée'}',
    );
    active.process?.kill(ProcessSignal.sigterm);
    _db.updateRecordingStatus(id, 'completed');
    unawaited(_finalizeStopped(active));
  }

  /// Attend la fin effective de FFmpeg puis clôture proprement (fusion + log).
  Future<void> _finalizeStopped(_ActiveRecording active) async {
    try {
      final process = active.process;
      if (process != null) {
        await process.exitCode.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
      await _finalize(active, status: 'completed');
    } catch (e, st) {
      print('[RecordingScheduler] ERREUR à la clôture: $e\n$st');
      await active.log?.close();
    }
  }

  String _fileNameFor(Recording recording) {
    // Génération d'un nom de fichier unique et sûr
    final safeTitle =
        recording.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final dateStr = recording.startTime
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')[0];
    return '${safeTitle}_$dateStr.mkv';
  }

  /// Chemin de la n-ième partie (la partie 1 étant le fichier principal).
  String _partPath(String filePath, int attempt) =>
      '${p.withoutExtension(filePath)}.part${attempt + 1}.mkv';

  /// Parties déjà écrites sur disque pour cet enregistrement, dans l'ordre.
  List<String> _existingParts(String filePath) {
    final parts = <String>[];
    for (var attempt = 1;; attempt++) {
      final path = _partPath(filePath, attempt);
      if (!_fileHasData(path)) break;
      parts.add(path);
    }
    return parts;
  }

  bool _activeHasData(_ActiveRecording active) =>
      _fileHasData(active.filePath) || active.extraParts.any(_fileHasData);

  bool _fileHasData(String? path) {
    if (path == null) return false;
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
