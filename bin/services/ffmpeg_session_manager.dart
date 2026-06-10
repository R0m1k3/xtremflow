import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One running FFmpeg transcoding session (live, VOD or recording playback).
class FfmpegSession {
  final String id;
  final Process process;
  final Directory dir;
  final bool isLive;
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

    // Clean shutdown for docker stop / Ctrl+C
    ProcessSignal.sigterm.watch().listen((_) {
      killAll();
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) {
      killAll();
      exit(0);
    });
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

  /// Waits until the session's playlist references at least one segment.
  /// Fails fast when the process dies before producing output, returning
  /// the recent stderr for diagnostics.
  Future<({bool ready, String? error})> waitForPlaylist(
    FfmpegSession session, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final playlistFile = File('${session.dir.path}/playlist.m3u8');
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (session.exited && session.exitCode != 0) {
        return (
          ready: false,
          error: 'FFmpeg exited (${session.exitCode}): '
              '${session.recentStderr.join().trim()}'
        );
      }
      if (playlistFile.existsSync() &&
          playlistFile.readAsStringSync().contains('.ts')) {
        return (ready: true, error: null);
      }
      await Future.delayed(const Duration(milliseconds: 500));
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
      if (session.exited || now.difference(session.lastAccess) > timeout) {
        print(
          '[FFmpegManager] Reaping idle session ${session.id} '
          '(idle ${now.difference(session.lastAccess).inSeconds}s)',
        );
        killSession(session.id);
      }
    }
  }
}
