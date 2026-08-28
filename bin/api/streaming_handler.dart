import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../models/playlist_config.dart';
import '../services/ffmpeg_session_manager.dart';
import '../utils/log_redactor.dart';

/// Directory for temporary HLS segments
final Directory _hlsTempDir =
    Directory('${Directory.systemTemp.path}/xtremflow_streams');

/// Global FFmpeg session registry (initialized in [initStreaming]).
final FfmpegSessionManager sessionManager = FfmpegSessionManager(_hlsTempDir);

/// Helper to resolve FFmpeg path (SYSTEM PATH vs Portable)
String _getFFmpegPath() {
  if (Platform.isWindows) {
    if (File('ffmpeg.exe').existsSync()) return 'ffmpeg.exe';
    if (File('bin/ffmpeg.exe').existsSync()) return 'bin/ffmpeg.exe';
    if (File('ffmpeg/bin/ffmpeg.exe').existsSync()) {
      return 'ffmpeg/bin/ffmpeg.exe';
    }
  }
  return 'ffmpeg'; // Default to PATH
}

/// Check if NVIDIA GPU acceleration is enabled via environment variable
bool _isNvidiaGpuEnabled() {
  final envValue = Platform.environment['NVIDIA_GPU'] ??
      Platform.environment['nvidia_gpu'] ??
      'false';
  return envValue.toLowerCase() == 'true' || envValue == '1';
}

/// Initialize streaming subsystem
Future<void> initStreaming() async {
  await sessionManager.init();
}

/// Supported quality presets. `source` skips video transcoding entirely
/// (`-c:v copy`) — a huge CPU win since most Xtream streams are already
/// H.264. Audio is always normalized to AAC for HLS compatibility.
const supportedQualities = {'source', 'high', 'medium', 'low'};

String _sanitizeQuality(String? quality) {
  return supportedQualities.contains(quality) ? quality! : 'high';
}

bool _isValidStreamId(String id) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);

/// Video encoding args for the requested quality (live profile).
List<String> _liveVideoArgs(String quality, bool gpu) {
  switch (quality) {
    case 'source':
      return ['-c:v', 'copy'];
    case 'medium':
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
              '-b:v', '3000k', '-maxrate', '4500k', '-bufsize', '6000k',
              '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p',
              '-g', '50',
            ]
          : [
              '-c:v', 'libx264', '-preset', 'veryfast', '-tune', 'zerolatency',
              '-profile:v', 'high', '-level', '4.0',
              '-b:v', '3000k', '-maxrate', '4500k', '-bufsize', '6000k',
              '-pix_fmt', 'yuv420p', '-g', '50',
            ];
    case 'low':
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4',
              '-b:v', '1500k', '-maxrate', '2000k', '-bufsize', '3000k',
              '-vf', 'scale=-2:720',
              '-pix_fmt', 'yuv420p', '-g', '50',
            ]
          : [
              '-c:v', 'libx264', '-preset', 'veryfast', '-tune', 'zerolatency',
              '-b:v', '1500k', '-maxrate', '2000k', '-bufsize', '3000k',
              '-vf', 'scale=-2:720',
              '-pix_fmt', 'yuv420p', '-g', '50',
            ];
    case 'high':
    default:
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
              '-b:v', '8000k', '-maxrate', '12000k', '-bufsize', '16000k',
              '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p',
              '-g', '50',
            ]
          : [
              // veryfast au lieu de medium : en live, l'encodeur doit tenir
              // le temps réel ET produire le premier segment vite ; medium
              // ajoutait plusieurs secondes au zap sans gain visible à ce
              // débit.
              '-c:v', 'libx264', '-preset', 'veryfast', '-tune', 'zerolatency',
              '-profile:v', 'high', '-level', '4.0',
              '-b:v', '6000k', '-maxrate', '8000k', '-bufsize', '12000k',
              '-pix_fmt', 'yuv420p', '-g', '50',
            ];
  }
}

/// Video encoding args for the requested quality (VOD profile).
List<String> _vodVideoArgs(String quality, bool gpu) {
  switch (quality) {
    case 'source':
      return ['-c:v', 'copy'];
    case 'medium':
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
              '-rc', 'cbr', '-b:v', '2500k', '-maxrate', '3000k',
              '-bufsize', '5000k', '-g', '48', '-bf', '2',
              '-pix_fmt', 'yuv420p',
            ]
          : [
              '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
              '-maxrate', '6000k', '-bufsize', '12000k',
              '-pix_fmt', 'yuv420p', '-g', '48', '-threads', '0',
            ];
    case 'low':
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4',
              '-rc', 'cbr', '-b:v', '1500k', '-maxrate', '2000k',
              '-bufsize', '3000k', '-vf', 'scale=-2:720',
              '-g', '48', '-pix_fmt', 'yuv420p',
            ]
          : [
              '-c:v', 'libx264', '-preset', 'fast', '-crf', '26',
              '-maxrate', '3000k', '-bufsize', '6000k',
              '-vf', 'scale=-2:720',
              '-pix_fmt', 'yuv420p', '-g', '48', '-threads', '0',
            ];
    case 'high':
    default:
      return gpu
          ? [
              '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
              '-rc', 'cbr', '-b:v', '4000k', '-maxrate', '4500k',
              '-bufsize', '8000k', '-g', '48', '-bf', '2',
              '-pix_fmt', 'yuv420p',
            ]
          : [
              '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
              '-maxrate', '12000k', '-bufsize', '24000k',
              '-pix_fmt', 'yuv420p', '-g', '48', '-threads', '0',
            ];
  }
}

/// Audio args. Source mode keeps it simple (plain AAC); transcoded modes
/// keep the downmix + loudness normalization filter.
List<String> _audioArgs({required bool withFilters}) {
  return [
    '-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-ar', '48000',
    if (withFilters)
      ...['-af',
          'pan=stereo|FL=1.0*FL+0.707*FC+0.5*BL+0.5*SL+0.5*LFE|FR=1.0*FR+0.707*FC+0.5*BR+0.5*SR+0.5*LFE,dynaudnorm=f=150:g=15']
    else
      ...['-af', 'aresample=async=1'],
  ];
}

Map<String, String> _hlsHeaders() => {
      'Content-Type': 'application/vnd.apple.mpegurl',
      'Cache-Control': 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    };

Map<String, String> _segmentHeaders({int maxAge = 60}) => {
      'Content-Type': 'video/mp2t',
      'Cache-Control': 'max-age=$maxAge',
    };

// ==========================================
// 1. LIVE TV HANDLER (FFmpeg HLS + direct TS proxy)
// ==========================================

/// Connexion amont ouverte, avec son client pour pouvoir le refermer.
class _LiveUpstream {
  final http.Client client;
  final http.StreamedResponse response;
  _LiveUpstream(this.client, this.response);
}

Future<_LiveUpstream?> _openLiveUpstream(String targetUrl) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(targetUrl))
      ..headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18'
      ..headers['Accept'] = '*/*';
    final response = await client.send(request);
    return _LiveUpstream(client, response);
  } catch (_) {
    client.close();
    return null;
  }
}

/// Nombre de reconnexions consécutives tentées avant d'abandonner le flux.
const _liveProxyMaxRetries = 4;

/// Corps du proxy `.ts` direct, avec reconnexion amont.
///
/// Les panneaux Xtream ferment régulièrement la connexion en cours de route
/// (bascule de source, limite de connexions simultanées, recyclage nginx).
/// Sans reprise, le `MediaSource` du navigateur reçoit un `sourceEnded` et la
/// lecture s'arrête net — le symptôme « ça coupe au bout de 30 s ».
/// On rouvre donc la source tant que le client, lui, écoute toujours.
///
/// Le compteur de tentatives est remis à zéro dès qu'une connexion a duré
/// assez longtemps pour être considérée saine : une coupure toutes les
/// 10 minutes ne doit pas finir par épuiser le quota.
Stream<List<int>> _resilientLiveBody(
  String streamId,
  String targetUrl,
  _LiveUpstream first,
) async* {
  var upstream = first;
  var attempt = 0;

  while (true) {
    final startedAt = DateTime.now();
    var bytes = 0;

    try {
      await for (final chunk in upstream.response.stream) {
        bytes += chunk.length;
        yield chunk;
      }
    } catch (e) {
      print('[Live Proxy] $streamId : coupure amont ($e)');
    } finally {
      upstream.client.close();
    }

    final lasted = DateTime.now().difference(startedAt);
    if (lasted > const Duration(seconds: 60) && bytes > 0) {
      attempt = 0;
    }

    print(
      '[Live Proxy] $streamId : flux terminé après ${lasted.inSeconds}s '
      '($bytes octets)',
    );

    // Rouvrir la source, en réessayant tant qu'il reste du quota.
    _LiveUpstream? next;
    while (next == null && attempt < _liveProxyMaxRetries) {
      attempt++;
      // Laisser le panneau libérer le slot de connexion précédent : sur les
      // comptes limités à une connexion simultanée, rouvrir immédiatement se
      // fait refuser.
      await Future<void>.delayed(const Duration(seconds: 1));

      final candidate = await _openLiveUpstream(targetUrl);
      if (candidate != null && candidate.response.statusCode == 200) {
        next = candidate;
      } else {
        candidate?.client.close();
        print(
          '[Live Proxy] $streamId : reconnexion '
          '$attempt/$_liveProxyMaxRetries échouée',
        );
      }
    }

    if (next == null) {
      print('[Live Proxy] $streamId : abandon, source injoignable');
      return;
    }
    upstream = next;
  }
}

Handler createLiveStreamHandler(
  Future<PlaylistConfig?> Function(Request) getPlaylist, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  Future<Response> servePlaylist(
    Request request,
    String streamId,
    String quality,
  ) async {
    if (!_isValidStreamId(streamId)) {
      return Response.badRequest(body: 'Invalid stream ID');
    }
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();
    final sessionId = 'live_${streamId}_$quality';

    if (!sessionManager.contains(sessionId)) {
      print(
        '[Live HLS] Starting $sessionId: ${LogRedactor.redactUrl(targetUrl)}',
      );
    }

    final session = await sessionManager.getOrStart(
      id: sessionId,
      isLive: true,
      ffmpegPath: _getFFmpegPath(),
      argsBuilder: (dir) => [
        '-hide_banner', '-loglevel', 'warning',
        if (useNvidiaGpu && quality != 'source') ...['-hwaccel', 'cuda'],
        '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
        '-reconnect', '1', '-reconnect_streamed', '1',
        '-reconnect_at_eof', '1',
        '-reconnect_delay_max', '10',
        // Abort reads stuck for 30s so a stalled upstream triggers the
        // reconnect logic instead of wedging the process forever.
        '-rw_timeout', '30000000',
        // Démarrage rapide : sans borne, FFmpeg peut passer plusieurs
        // secondes à sonder le flux avant d'écrire le premier segment.
        '-fflags', 'nobuffer',
        '-probesize', '1000000',
        '-analyzeduration', '1000000',
        '-i', targetUrl,
        ..._liveVideoArgs(quality, useNvidiaGpu),
        ..._audioArgs(withFilters: false),
        // HLS sliding window: 10 x 2s segments (lower live latency than the
        // previous 20-segment window while still safe for iOS).
        // hls_init_time 1: first segment closes after ~1s so playback can
        // start sooner; subsequent segments use hls_time.
        '-f', 'hls',
        '-hls_init_time', '1',
        '-hls_time', '2',
        '-hls_list_size', '10',
        '-hls_flags', 'delete_segments+independent_segments',
        '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', 'seg_%03d.ts',
        'playlist.m3u8',
      ],
    );

    final result = await sessionManager.waitForPlaylist(session);
    if (!result.ready) {
      sessionManager.killSession(sessionId);
      return Response(502, body: 'Live transcoder failed: ${result.error}');
    }

    session.touch();
    return Response.ok(
      File('${session.dir.path}/playlist.m3u8').openRead(),
      headers: _hlsHeaders(),
    );
  }

  // Route: /api/live/{streamId}/{quality}/playlist.m3u8
  router.get('/<streamId>/<quality>/playlist.m3u8',
      (Request request, String streamId, String quality) {
    return servePlaylist(request, streamId, _sanitizeQuality(quality));
  });

  // Back-compat route: /api/live/{streamId}/playlist.m3u8 (?quality=...)
  // Redirects so relative segment URLs resolve inside the quality path.
  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final quality =
        _sanitizeQuality(request.url.queryParameters['quality']);
    return Response.found('/api/live/$streamId/$quality/playlist.m3u8');
  });

  // Route: /api/live/{streamId}/turbo.ts — flux MPEG-TS continu pour le
  // player web (mpegts.js) : vidéo copiée telle quelle, audio TOUJOURS
  // réencodé en AAC.
  //
  // POURQUOI : mpegts.js ne démuxe que l'AAC et le MP3. Les chaînes qui
  // diffusent en AC-3/E-AC-3 (0x81/0x87) ou en MPEG-1 Layer II passaient par
  // le proxy brut → image sans aucun son. Le réencodage audio seul coûte
  // quelques % de CPU (pas de transcodage vidéo) et garde le zapping
  // instantané : un seul flux continu, pas de segmentation HLS à amorcer.
  //
  // Latence : -fflags nobuffer + probesize réduit → première image en
  // ~0,5-1,5 s au lieu des 2-6 s d'analyse par défaut de FFmpeg.
  router.get('/<streamId>/turbo.ts', (Request request, String streamId) async {
    if (!_isValidStreamId(streamId)) {
      return Response.badRequest(body: 'Invalid stream ID');
    }
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    print(
      '[Live Turbo] $streamId: ${LogRedactor.redactUrl(targetUrl)}',
    );

    final process = await Process.start(_getFFmpegPath(), [
      '-hide_banner', '-loglevel', 'warning',
      '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
      '-reconnect', '1', '-reconnect_streamed', '1',
      '-reconnect_at_eof', '1',
      '-reconnect_delay_max', '10',
      '-rw_timeout', '30000000',
      // Démarrage rapide : ne pas bufferiser l'analyse, sonde réduite.
      '-fflags', 'nobuffer',
      '-flags', 'low_delay',
      '-probesize', '1000000',
      '-analyzeduration', '1000000',
      '-i', targetUrl,
      '-c:v', 'copy',
      '-c:a', 'aac', '-b:a', '160k', '-ac', '2', '-ar', '48000',
      '-af', 'aresample=async=1',
      // Pas de délai de mux : les paquets partent dès qu'ils existent.
      '-muxdelay', '0', '-muxpreload', '0',
      '-f', 'mpegts', 'pipe:1',
    ]);

    // Journaliser les erreurs FFmpeg (redactées) sans bloquer le flux.
    process.stderr.transform(const SystemEncoding().decoder).listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        print('[Live Turbo] $streamId ffmpeg: '
            '${LogRedactor.redactUrl(trimmed)}');
      }
    });

    // Relayer stdout vers le client ; tuer FFmpeg dès que le client zappe
    // ou ferme l'onglet (sinon les processus s'accumulent à chaque zap).
    final controller = StreamController<List<int>>();
    final subscription = process.stdout.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () {
      subscription.cancel();
      process.kill(ProcessSignal.sigterm);
    };

    return Response(
      200,
      body: controller.stream,
      headers: {
        'Content-Type': 'video/mp2t',
        'Cache-Control': 'no-store',
        'Connection': 'keep-alive',
      },
    );
  });

  // Route: /api/live/{streamId}.ts (Direct Proxy for recordings/raw playback)
  router.get('/<streamId>.ts', (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    print(
        '[Live Proxy] Forwarding $streamId: ${LogRedactor.redactUrl(targetUrl)}');

    // Première connexion faite hors du générateur : elle seule décide du code
    // de réponse renvoyé au client.
    final first = await _openLiveUpstream(targetUrl);
    if (first == null) {
      return Response(502, body: 'Upstream connection failed');
    }
    if (first.response.statusCode != 200) {
      first.client.close();
      return Response(first.response.statusCode, body: 'Upstream refused');
    }

    return Response(
      200,
      body: _resilientLiveBody(streamId, targetUrl, first),
      headers: {
        'Content-Type': 'video/mp2t',
        'Connection': 'keep-alive',
      },
    );
  });

  // Route: /api/live/{streamId}/{quality}/{segment}
  router.get('/<streamId>/<quality>/<segment>',
      (Request request, String streamId, String quality, String segment) {
    if (!_isValidStreamId(streamId) || segment.contains('..')) {
      return Response.badRequest(body: 'Invalid request');
    }
    final sessionId = 'live_${streamId}_${_sanitizeQuality(quality)}';
    sessionManager.touch(sessionId);
    final file = File('${_hlsTempDir.path}/$sessionId/$segment');
    if (!file.existsSync()) return Response.notFound('Segment not found');

    return Response.ok(file.openRead(), headers: _segmentHeaders());
  });

  return router.call;
}

// ==========================================
// 2. VOD HANDLER (FFmpeg HLS Transcoding)
// ==========================================

Handler createVodStreamHandler(
  Future<PlaylistConfig?> Function(Request) getPlaylist, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  Future<Response> servePlaylist(
    Request request,
    String streamId,
    String quality,
  ) async {
    if (!_isValidStreamId(streamId)) {
      return Response.badRequest(body: 'Invalid stream ID');
    }
    final playlist = await getPlaylist(request);
    if (playlist == null) {
      return Response.internalServerError(body: 'No playlist');
    }

    // ?type=series or ?type=movie selects the upstream path
    final contentType = request.url.queryParameters['type'] ?? 'movie';
    final basePath = contentType == 'series' ? 'series' : 'movie';

    final targetUrl =
        '${playlist.dns}/$basePath/${playlist.username}/${playlist.password}/$streamId.mkv';
    final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();
    final sessionId = 'vod_${streamId}_$quality';

    if (!sessionManager.contains(sessionId)) {
      print(
        '[VOD] Starting $sessionId ($contentType): ${LogRedactor.redactUrl(targetUrl)}',
      );
    }

    final session = await sessionManager.getOrStart(
      id: sessionId,
      isLive: false,
      ffmpegPath: _getFFmpegPath(),
      argsBuilder: (dir) => [
        '-hide_banner', '-loglevel', 'warning',
        if (useNvidiaGpu && quality != 'source') ...['-hwaccel', 'cuda'],
        '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
        '-reconnect', '1',
        '-reconnect_at_eof', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '10',
        '-rw_timeout', '30000000',
        '-timeout', '30000000',
        // Sonde réduite (10 Mo → 5 Mo) : sur un upstream lent, télécharger
        // 10 Mo avant la première image ajoutait plusieurs secondes au
        // démarrage de chaque film.
        '-analyzeduration', '2000000',
        '-probesize', '5000000',
        '-i', targetUrl,
        ..._vodVideoArgs(quality, useNvidiaGpu),
        ..._audioArgs(withFilters: quality != 'source'),
        '-f', 'hls',
        '-hls_time', '4',
        '-hls_list_size', '0',
        '-hls_playlist_type', 'event',
        '-hls_allow_cache', '1',
        '-hls_flags', 'independent_segments',
        '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', 'segment_%03d.ts',
        '-start_number', '0',
        'playlist.m3u8',
      ],
    );

    final result = await sessionManager.waitForPlaylist(session);
    if (!result.ready) {
      sessionManager.killSession(sessionId);
      return Response(502, body: 'VOD transcoder failed: ${result.error}');
    }

    session.touch();
    return Response.ok(
      File('${session.dir.path}/playlist.m3u8').openRead(),
      headers: _hlsHeaders(),
    );
  }

  // Route: /api/vod/{streamId}/{quality}/playlist.m3u8
  router.get('/<streamId>/<quality>/playlist.m3u8',
      (Request request, String streamId, String quality) {
    return servePlaylist(request, streamId, _sanitizeQuality(quality));
  });

  // Back-compat route: /api/vod/{streamId}/playlist.m3u8 (?quality=...)
  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final quality =
        _sanitizeQuality(request.url.queryParameters['quality']);
    final query = request.url.queryParameters['type'] != null
        ? '?type=${request.url.queryParameters['type']}'
        : '';
    return Response.found('/api/vod/$streamId/$quality/playlist.m3u8$query');
  });

  // Route: /api/vod/{streamId}/{quality}/{segment}
  router.get('/<streamId>/<quality>/<segment>',
      (Request request, String streamId, String quality, String segment) {
    if (!_isValidStreamId(streamId) || segment.contains('..')) {
      return Response.badRequest(body: 'Invalid request');
    }
    final sessionId = 'vod_${streamId}_${_sanitizeQuality(quality)}';
    sessionManager.touch(sessionId);
    final file = File('${_hlsTempDir.path}/$sessionId/$segment');
    if (!file.existsSync()) return Response.notFound('Segment not found');

    return Response.ok(file.openRead(), headers: _segmentHeaders(maxAge: 3600));
  });

  return router.call;
}

// ==========================================
// 3. RECORDING HANDLER (FFmpeg HLS Transcoding)
// ==========================================

Handler createRecordingStreamHandler(
  AppDatabase db, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final recording = db.getRecordingById(streamId);
    if (recording == null) {
      return Response.notFound('Recording not found');
    }

    // Check recording status - only allow streaming if completed or recording
    if (recording.status == 'scheduled') {
      return Response(202, body: 'Recording not yet started');
    }
    if (recording.status == 'failed') {
      return Response(422,
          body: 'Recording failed: ${recording.errorReason ?? 'unknown error'}');
    }
    if (recording.status != 'completed' && recording.status != 'recording') {
      return Response.internalServerError(
          body: 'Invalid recording status: ${recording.status}');
    }

    if (recording.filePath == null) {
      return Response.internalServerError(body: 'Recording file path not set');
    }

    final targetUrl = recording.filePath!;
    if (!File(targetUrl).existsSync()) {
      return Response.internalServerError(
          body: 'Physical recording file not found');
    }

    final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();
    final sessionId = 'rec_$streamId';

    final session = await sessionManager.getOrStart(
      id: sessionId,
      isLive: false,
      ffmpegPath: _getFFmpegPath(),
      argsBuilder: (dir) => [
        '-hide_banner', '-loglevel', 'warning',
        if (useNvidiaGpu) ...['-hwaccel', 'cuda'],
        '-i', targetUrl,
        if (useNvidiaGpu) ...[
          '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
          '-rc', 'cbr', '-b:v', '3000k', '-maxrate', '3500k',
          '-bufsize', '6000k',
          '-g', '48', '-bf', '2', '-pix_fmt', 'yuv420p',
        ] else ...[
          // veryfast/crf 20 au lieu de medium/crf 18 : à ce niveau le rendu
          // est visuellement identique, mais medium ne tenait pas le temps
          // réel en 1080p sur un CPU modeste → lecture d'enregistrement qui
          // démarre lentement puis bufferise.
          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
          '-maxrate', '12000k', '-bufsize', '24000k', '-pix_fmt', 'yuv420p',
          '-g', '48', '-threads', '0',
        ],
        ..._audioArgs(withFilters: true),
        '-f', 'hls', '-hls_time', '4', '-hls_list_size', '0',
        '-hls_playlist_type', 'vod', '-hls_allow_cache', '1',
        '-hls_flags', 'independent_segments', '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', 'segment_%03d.ts', '-start_number', '0',
        'playlist.m3u8',
      ],
    );

    final result = await sessionManager.waitForPlaylist(session);
    if (!result.ready) {
      sessionManager.killSession(sessionId);
      return Response(502,
          body: 'Recording transcoder failed: ${result.error}');
    }

    session.touch();
    return Response.ok(
      File('${session.dir.path}/playlist.m3u8').openRead(),
      headers: _hlsHeaders(),
    );
  });

  router.get('/<streamId>/<segment>',
      (Request request, String streamId, String segment) async {
    if (segment.contains('..')) {
      return Response.badRequest(body: 'Invalid request');
    }
    final sessionId = 'rec_$streamId';
    sessionManager.touch(sessionId);
    final file = File('${_hlsTempDir.path}/$sessionId/$segment');
    if (!file.existsSync()) return Response.notFound('Segment not found');
    return Response.ok(file.openRead(), headers: _segmentHeaders(maxAge: 3600));
  });

  return router.call;
}
