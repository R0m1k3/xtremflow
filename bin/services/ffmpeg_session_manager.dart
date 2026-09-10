import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One running FFmpeg transcoding session (live, VOD or recording playback).
class FfmpegSession {
  final String id;
  final Process process;
  final Directory dir;
  final bool isLive;
  final DateTime startedAt = DateTime.now();
  DateTime lastAccess = DateTime.now();
  bool exited = false;
  int? exitCode;

  /// Last stderr lines, kept for fast-fail diagnostics.
  final List<String> recentStderr = [];

  FfmpegSession({
    required this.id,
    required this.process,
    required this.dir,
    required this.isLive,
  });

  void touch() => lastAccess = DateTime.now();
}

/// Registry of FFmpeg transcoding processes.
///
/// Responsibilities:
/// - one process per session id (`live_{id}_{quality}`, `vod_{id}`, ...)
/// - reaper kills sessions idle beyond a TTL (no viewer fetching segments)
/// - startup wipe of the HLS temp dir (orphan dirs after a crash)
/// - SIGTERM/SIGINT hook so `docker stop` leaves no orphan ffmpeg
class FfmpegSessionManager {
  final Directory baseDir;
  final Map<String, FfmpegSession> _sessions = {};
  Timer? _reaper;

  static const liveIdleTimeout = Duration(minutes: 4);
  static const vodIdleTimeout = Duration(minutes: 15);

  /// Live playlist not rewritten for this long => FFmpeg is wedged.
  static const liveStallTimeout = Duration(seconds: 45);

  FfmpegSessionManager(this.baseDir);

  /// Wipe orphan session dirs and start the reaper. Call once at startup.
  Future<void> init() async {
    if (baseDir.existsSync()) {
      try {
        baseDir.deleteSync(recursive: true);
      } catch (e) {
        print('[FFmpegManager] Could not wipe temp dir: $e');
      }
    }
    baseDir.createSync(recursive: true);

    _reaper = Timer.periodic(const Duration(seconds: 60), (_) => _reap());

    // L'arrêt propre (docker stop / Ctrl+C) est orchestré par server.dart :
    // il clôture d'abord les enregistrements puis appelle killAll(). Un
    // handler local qui ferait exit(0) immédiatement court-circuiterait
    // cette clôture.
  }

  FfmpegSession? get(String id) => _sessions[id];

  /// Marks a session as recently used (call from playlist AND segment routes).
  void touch(String id) => _sessions[id]?.touch();

  bool contains(String id) => _sessions.containsKey(id);

  /// Returns the existing healthy session or starts a new FFmpeg process.
  ///
  /// [argsBuilder] receives the session working directory and returns the
  /// FFmpeg argument list. The session directory is recreated for new
  /// sessions.
  Future<FfmpegSession> getOrStart({
    required String id,
    required bool isLive,
    required String ffmpegPath,
    required List<String> Function(Directory dir) argsBuilder,
  }) async {
    final existing = _sessions[id];
    if (existing != null && !existing.exited) {
      existing.touch();
      return existing;
    }
    if (existing != null) {
      // A VOD/recording transcode that finished cleanly is still fully
      // playable from its segments — reuse it instead of re-transcoding.
      if (!isLive && existing.exitCode == 0 && _playlistComplete(existing)) {
        existing.touch();
        return existing;
      }
      // Process died: clean up before restarting
      killSession(id);
    }

    final dir = Directory('${baseDir.path}/$id');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    final args = argsBuilder(dir);
    final process = await Process.start(
      ffmpegPath,
      args,
      workingDirectory: dir.path,
    );

    final session = FfmpegSession(
      id: id,
      process: process,
      dir: dir,
      isLive: isLive,
    );
    _sessions[id] = session;

    process.stderr.transform(utf8.decoder).listen((data) {
      session.recentStderr.add(data);
      if (session.recentStderr.length > 20) session.recentStderr.removeAt(0);
      print('[FFmpeg $id] $data');
    });

    process.exitCode.then((code) {
      session.exited = true;
      session.exitCode = code;
      print('[FFmpegManager] Session $id exited with code $code');
    });

    return session;
  }

  bool _playlistComplete(FfmpegSession session) {
    final playlistFile = File('${session.dir.path}/playlist.m3u8');
    if (!playlistFile.existsSync()) return false;
    try {
      return playlistFile.readAsStringSync().contains('#EXT-X-ENDLIST');
    } catch (_) {
      return false;
    }
  }

  /// Waits until the session's playlist references at least [minSegments]
  /// segments. Fails fast when the process dies before producing output,
  /// returning the recent stderr for diagnostics.
  ///
  /// [minSegments] > 1 donne au lecteur une avance de démarrage : servir la
  /// playlist dès le premier segment le fait partir avec 4 s de marge sur un
  /// encodeur qui n'a pas fini — la moindre hésitation coupe la lecture. La
  /// playlist déjà close (`#EXT-X-ENDLIST`) est renvoyée telle quelle, quel
  /// que soit son nombre de segments : rien de plus n'arrivera.
  Future<({bool ready, String? error})> waitForPlaylist(
    FfmpegSession session, {
    Duration timeout = const Duration(seconds: 30),
    int minSegments = 1,
  }) async {
    final playlistFile = File('${session.dir.path}/playlist.m3u8');
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (playlistFile.existsSync()) {
        final content = playlistFile.readAsStringSync();
        final segments = '.ts'.allMatches(content).length;
        if (segments >= minSegments ||
            (segments > 0 && content.contains('#EXT-X-ENDLIST'))) {
          return (ready: true, error: null);
        }
      }
      if (session.exited) {
        // Un encodeur qui s'est terminé proprement en ayant produit moins de
        // segments que demandé a simplement fini : c'est un succès.
        if (session.exitCode == 0 &&
            playlistFile.existsSync() &&
            playlistFile.readAsStringSync().contains('.ts')) {
          return (ready: true, error: null);
        }
        return (
          ready: false,
          error: 'FFmpeg exited (${session.exitCode}): '
              '${session.recentStderr.join().trim()}'
        );
      }
      // 100 ms : à 500 ms, on ajoutait en moyenne un quart de seconde de
      // latence pure entre la disponibilité de la playlist et sa réponse.
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Le délai est écoulé : mieux vaut servir ce qui existe que rien.
    if (playlistFile.existsSync() &&
        playlistFile.readAsStringSync().contains('.ts')) {
      return (ready: true, error: null);
    }
    return (ready: false, error: 'Timeout waiting for transcoder');
  }

  void killSession(String id) {
    final session = _sessions.remove(id);
    if (session == null) return;
    try {
      session.process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      if (session.dir.existsSync()) session.dir.deleteSync(recursive: true);
    } catch (e) {
      print('[FFmpegManager] Could not delete dir for $id: $e');
    }
  }

  /// Tue les sessions frères d'un même contenu (`rec_<id>_t0`, `rec_<id>_t600`…)
  /// que plus personne ne consomme depuis [idleFor].
  ///
  /// Chaque saut hors de la zone déjà transcodée démarre un FFmpeg à un
  /// nouvel offset ; sans ce ménage, une poignée d'allers-retours dans la
  /// barre de progression laisserait autant de processus vivants jusqu'au
  /// TTL de 15 minutes. Le délai d'inactivité protège un second spectateur
  /// du même enregistrement : sa session est « touchée » à chaque segment.
  void killIdleSiblings(
    String prefix, {
    required String keep,
    Duration idleFor = const Duration(seconds: 30),
  }) {
    final now = DateTime.now();
    for (final session in _sessions.values.toList()) {
      if (session.id == keep || !session.id.startsWith(prefix)) continue;
      if (now.difference(session.lastAccess) < idleFor) continue;
      print('[FFmpegManager] Dropping stale sibling ${session.id}');
      killSession(session.id);
    }
  }

  void killAll() {
    print('[FFmpegManager] Killing ${_sessions.length} session(s)');
    for (final id in _sessions.keys.toList()) {
      killSession(id);
    }
    _reaper?.cancel();
  }

  void _reap() {
    final now = DateTime.now();
    for (final session in _sessions.values.toList()) {
      final timeout = session.isLive ? liveIdleTimeout : vodIdleTimeout;
      final idle = now.difference(session.lastAccess);

      // Exited sessions keep their segments until the idle timeout: a
      // finished VOD transcode is usually still being watched, and killing
      // it here would delete the segments mid-playback.
      if (idle > timeout) {
        print(
          '[FFmpegManager] Reaping idle session ${session.id} '
          '(idle ${idle.inSeconds}s)',
        );
        killSession(session.id);
        continue;
      }

      // Watchdog: a live FFmpeg that is running but has not updated its
      // playlist recently is wedged on a stalled upstream. Kill it so the
      // player's next playlist poll restarts the transcoder.
      if (session.isLive && !session.exited && _isStalled(session, now)) {
        print('[FFmpegManager] Restarting stalled live session ${session.id}');
        killSession(session.id);
      }
    }
  }

  /// A live session is stalled when its playlist exists but has not been
  /// rewritten for [liveStallTimeout] (FFmpeg rewrites it on every segment).
  bool _isStalled(FfmpegSession session, DateTime now) {
    final playlistFile = File('${session.dir.path}/playlist.m3u8');
    if (!playlistFile.existsSync()) {
      // Never produced output: give it until liveStallTimeout after start.
      return now.difference(session.startedAt) > liveStallTimeout;
    }
    try {
      return now.difference(playlistFile.lastModifiedSync()) >
          liveStallTimeout;
    } catch (_) {
      return false;
    }
  }
}
