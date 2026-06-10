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
              '-c:v', 'libx264', '-preset', 'medium', '-tune', 'zerolatency',
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
        '-reconnect_delay_max', '10',
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

  // Route: /api/live/{streamId}.ts (Direct Proxy for recordings/raw playback)
  router.get('/<streamId>.ts', (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    print('[Live Proxy] Forwarding $streamId: ${LogRedactor.redactUrl(targetUrl)}');

    final client = http.Client();
    final proxyRequest = http.Request('GET', Uri.parse(targetUrl));
    proxyRequest.headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18';
    proxyRequest.headers['Accept'] = '*/*';

    final response = await client.send(proxyRequest);

    return Response(
      response.statusCode,
      body: response.stream,
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
        '-analyzeduration', '5000000',
        '-probesize', '10000000',
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
          '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
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
