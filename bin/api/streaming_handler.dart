import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../models/playlist_config.dart';

/// Active FFmpeg processes for VOD transcoding
final Map<String, Process> _vodProcesses = {};

/// Directory for temporary HLS segments
final Directory _hlsTempDir =
    Directory('${Directory.systemTemp.path}/xtremflow_streams');

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

/// Log GPU status on first use
bool _gpuStatusLogged = false;
void _logGpuStatus() {
  if (!_gpuStatusLogged) {
    if (_isNvidiaGpuEnabled()) {
      print('[FFmpeg] NVIDIA GPU acceleration ENABLED (NVDEC/NVENC)');
    } else {
      print(
        '[FFmpeg] Using CPU processing (set NVIDIA_GPU=true to enable GPU)',
      );
    }
    _gpuStatusLogged = true;
  }
}

/// Initialize streaming subsystem
Future<void> initStreaming() async {
  if (!_hlsTempDir.existsSync()) {
    await _hlsTempDir.create(recursive: true);
  }
}

/// Helper to resolve HTTP redirects and get final URL
/// Some IPTV servers return 302 redirects that FFmpeg doesn't follow properly
Future<String> _resolveRedirects(String url, {int maxRedirects = 5}) async {
  String currentUrl = url;
  final client = http.Client();

  try {
    for (int i = 0; i < maxRedirects; i++) {
      final request = http.Request('GET', Uri.parse(currentUrl));
      request.headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18';
      request.followRedirects = false;

      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw TimeoutException('Redirect resolution timeout'),
          );

      // Check if it's a redirect (301, 302, 307, 308)
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          // Handle relative URLs
          if (location.startsWith('/')) {
            final uri = Uri.parse(currentUrl);
            currentUrl = '${uri.scheme}://${uri.host}:${uri.port}$location';
          } else {
            currentUrl = location;
          }
          print('[Redirect] $i: $url -> $currentUrl');
          await response.stream.drain();
          continue;
        }
      }

      // Not a redirect - we're done
      await response.stream.drain();
      break;
    }
  } catch (e) {
    print('[Redirect] Error resolving redirects: $e');
    // Return original URL if redirect resolution fails
  } finally {
    client.close();
  }

  return currentUrl;
}

/// Helper to get current playlist configuration (mocked for now, implies single user)
/// In a real scenario, this should come from the request session/context
PlaylistConfig? _getCurrentPlaylist(Request request) {
  // TODO: Retrieve from DB/Session based on Auth
  // For now, we assume the frontend sends enough info or we look up the active one
  return null; // Implemented later in server.dart injection
}

// ==========================================
// 1. LIVE TV HANDLER (Direct MPEG-TS Proxy)
// ==========================================

/// Active FFmpeg processes for Live HLS transcoding
final Map<String, Process> _liveProcesses = {};

Handler createLiveStreamHandler(
  Future<PlaylistConfig?> Function(Request) getPlaylist, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  // Route: /api/live/{streamId}/playlist.m3u8 (Master playlist)
  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final streamDir = Directory('${_hlsTempDir.path}/live_$streamId');

    // Start FFmpeg if not already running for this live stream
    if (!_liveProcesses.containsKey(streamId)) {
      if (streamDir.existsSync()) streamDir.deleteSync(recursive: true);
      streamDir.createSync(recursive: true);

      final targetUrl =
          '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
      print('[Live HLS] Starting for $streamId: $targetUrl');

      final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();
      final ffmpegArgs = <String>[
        '-hide_banner', '-loglevel', 'warning',
        if (useNvidiaGpu) ...['-hwaccel', 'cuda'],
        '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
        '-reconnect', '1', '-reconnect_streamed', '1',
        '-reconnect_delay_max', '10',
        '-i', targetUrl,
        // Video
        if (useNvidiaGpu) ...[
          '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune',
          'hq',
          '-b:v', '8000k', '-maxrate', '12000k', '-bufsize', '16000k',
          '-profile:v', 'high', '-level', '4.0',
          '-pix_fmt', 'yuv420p',
          '-g', '50',
        ] else ...[
          '-c:v', 'libx264', '-preset', 'medium', '-tune', 'zerolatency',
          '-profile:v', 'high', '-level', '4.0',
          '-b:v', '6000k', '-maxrate', '8000k', '-bufsize', '12000k',
          '-pix_fmt', 'yuv420p',
          '-g', '50',
        ],
        // Audio: High quality + Sync filter
        '-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-ar', '48000',
        '-af', 'aresample=async=1',
        // HLS Sliding Window — larger window so iOS never requests a deleted segment
        '-f', 'hls',
        '-hls_time', '2',
        '-hls_list_size', '20',
        '-hls_flags', 'delete_segments+independent_segments',
        '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', 'seg_%03d.ts',
        'playlist.m3u8',
      ];

      final process = await Process.start(
        _getFFmpegPath(),
        ffmpegArgs,
        workingDirectory: streamDir.path,
      );
      _liveProcesses[streamId] = process;

      process.stderr
          .transform(utf8.decoder)
          .listen((d) => print('[Live HLS $streamId] $d'));
      process.exitCode.then((_) => _liveProcesses.remove(streamId));
    }

    // Wait for playlist AND at least one segment reference
    final file = File('${streamDir.path}/playlist.m3u8');
    int retries = 0;
    while (retries < 60) {
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        // Live HLS needs at least 2 or 3 segments to be stable on iOS
        // but we start as soon as we have one for speed
        if (content.contains('.ts')) break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (!file.existsSync()) {
      return Response.internalServerError(body: 'Timeout starting live HLS');
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/vnd.apple.mpegurl',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache',
        'X-Content-Type-Options': 'nosniff',
      },
    );
  });

  // Route: /api/live/{streamId}.ts (Direct Proxy for internal recordings or raw playback)
  router.get('/<streamId>.ts', (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.forbidden('No playlist');

    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    print('[Live Proxy] Forwarding $streamId: $targetUrl');

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
        'Access-Control-Allow-Origin': '*',
        'Connection': 'keep-alive',
      },
    );
  });

  // Route: /api/live/{streamId}/{segment}
  router.get('/<streamId>/<segment>',
      (Request request, String streamId, String segment) async {
    final file = File('${_hlsTempDir.path}/live_$streamId/$segment');
    if (!file.existsSync()) return Response.notFound('Segment not found');

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'max-age=60',
      },
    );
  });

  return router;
}

// ==========================================
// 2. VOD HANDLER (FFmpeg HLS Transcoding)
// ==========================================

// ==========================================
// 2. VOD HANDLER (FFmpeg HLS Transcoding)
// ==========================================

final _lastLogTime = <String, int>{};

Handler createVodStreamHandler(
  Future<PlaylistConfig?> Function(Request) getPlaylist, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  // Route: /api/vod/{streamId}/playlist.m3u8
  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) {
      return Response.internalServerError(body: 'No playlist');
    }

    // Validate streamId to prevent Path Traversal
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(streamId)) {
      return Response.badRequest(body: 'Invalid stream ID');
    }

    final streamDir = Directory('${_hlsTempDir.path}/$streamId');

    // Check if existing session is healthy
    if (_vodProcesses.containsKey(streamId)) {
      final existingProcess = _vodProcesses[streamId]!;

      // Check if process is still running by checking if playlist exists and has content
      final playlistFile = File('${streamDir.path}/playlist.m3u8');
      if (playlistFile.existsSync()) {
        final content = playlistFile.readAsStringSync();
        // Check if playlist has segments (healthy transcoding)
        if (content.contains('.ts')) {
          // Only log once per second to avoid spam
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!_lastLogTime.containsKey(streamId) ||
              (now - _lastLogTime[streamId]! > 2000)) {
            print('[VOD] Reusing existing session for $streamId');
            _lastLogTime[streamId] = now;
          }
          // Serve existing playlist
          return Response.ok(
            playlistFile.openRead(),
            headers: {
              'Content-Type': 'application/vnd.apple.mpegurl',
              'Access-Control-Allow-Origin': '*',
              'Cache-Control': 'no-cache',
            },
          );
        }
      }

      // Playlist missing or empty - process likely failed, clean up
      print('[VOD] Cleaning up stale session for $streamId');
      try {
        existingProcess.kill();
      } catch (e) {
        // Process may already be dead
      }
      _vodProcesses.remove(streamId);

      // Clean up directory
      if (streamDir.existsSync()) {
        try {
          streamDir.deleteSync(recursive: true);
        } catch (e) {
          print('[VOD] Failed to clean directory: $e');
        }
      }
    }

    // Build Upstream URL based on content type
    // Check for type parameter in request URL (?type=series or ?type=movie)
    final contentType = request.url.queryParameters['type'] ?? 'movie';
    final basePath = contentType == 'series' ? 'series' : 'movie';

    // Only start FFmpeg if not already running
    if (!_vodProcesses.containsKey(streamId)) {
      // Prepare directory (Only for new session)
      if (streamDir.existsSync()) {
        streamDir.deleteSync(recursive: true);
      }
      streamDir.createSync(recursive: true);

      final targetUrl =
          '${playlist.dns}/$basePath/${playlist.username}/${playlist.password}/$streamId.mkv';
      print('[VOD] Starting Transcode ($contentType): $targetUrl');

      // Check if NVIDIA GPU is enabled (from database setting or env var fallback)
      final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();

      if (useNvidiaGpu) {
        print('[VOD] Using NVIDIA GPU acceleration (NVENC)');
      }

      // Build FFmpeg arguments
      final ffmpegArgs = <String>[
        '-hide_banner',
        '-loglevel',
        'warning',
      ];

      // NVIDIA GPU Hardware Acceleration
      if (useNvidiaGpu) {
        ffmpegArgs.addAll([
          '-hwaccel', 'cuda',
          // Note: Don't use hwaccel_output_format cuda - it can cause issues
        ]);
      }

      // Input and robustness flags
      ffmpegArgs.addAll([
        '-headers',
        'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
        '-reconnect',
        '1',
        '-reconnect_at_eof',
        '1',
        '-reconnect_streamed',
        '1',
        '-reconnect_delay_max',
        '10',
        '-rw_timeout',
        '30000000',
        '-timeout',
        '30000000',
        '-analyzeduration',
        '5000000',
        '-probesize',
        '10000000',
        '-i',
        targetUrl,
      ]);

      // Video encoding (GPU or CPU)
      if (useNvidiaGpu) {
        // NVIDIA NVENC - Hardware encoding (50x+ faster, much lower CPU)
        ffmpegArgs.addAll([
          '-c:v', 'h264_nvenc', // Use NVIDIA NVENC encoder
          '-preset', 'p4', // Good quality/speed balance
          '-tune', 'hq', // High quality mode
          '-rc', 'cbr', // Constant bitrate for HLS
          '-b:v', '4000k', // Target bitrate
          '-maxrate', '4500k',
          '-bufsize', '8000k',
          '-g', '48', // Keyframe every 2 seconds
          '-bf', '2', // B-frames for quality
          '-pix_fmt', 'yuv420p',
        ]);
      } else {
        // CPU encoding (libx264)
        ffmpegArgs.addAll([
          '-c:v',
          'libx264',
          '-preset',
          'medium', // Quality over raw speed for VOD
          '-crf',
          '18', // Near-native visual quality
          '-maxrate',
          '12000k',
          '-bufsize',
          '24000k',
          '-pix_fmt',
          'yuv420p',
          '-g', '48',
          '-threads',
          '0',
        ]);
      }

      // Audio encoding (same for both)
      ffmpegArgs.addAll([
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-ar',
        '48000',
        '-af',
        'pan=stereo|FL=1.0*FL+0.707*FC+0.5*BL+0.5*SL+0.5*LFE|FR=1.0*FR+0.707*FC+0.5*BR+0.5*SR+0.5*LFE,dynaudnorm=f=150:g=15',
      ]);

      // HLS output settings
      ffmpegArgs.addAll([
        '-f',
        'hls',
        '-hls_time',
        '4',
        '-hls_list_size',
        '0',
        '-hls_playlist_type',
        'event',
        '-hls_allow_cache',
        '1',
        '-hls_flags',
        'independent_segments',
        '-hls_segment_type',
        'mpegts',
        '-hls_segment_filename',
        'segment_%03d.ts',
        '-start_number',
        '0',
        'playlist.m3u8',
      ]);

      final ffmpegPath = _getFFmpegPath();
      Process.start(
        ffmpegPath,
        ffmpegArgs,
        workingDirectory: streamDir.path,
      ).then((process) {
        _vodProcesses[streamId] = process;

        process.stderr.transform(utf8.decoder).listen((data) {
          // Log only major errors or startup info to keep logs clean(er)
          // or keep verbose if debugging
          print('[FFmpeg $streamId] $data');
        });

        process.exitCode.then((code) {
          print('[VOD] FFmpeg exited with code $code');
          _vodProcesses.remove(streamId);
        });
      });
    }

    // Wait for playlist AND at least one segment to be referenced
    final playlistFile = File('${streamDir.path}/playlist.m3u8');
    int retries = 0;
    while (retries < 60) {
      if (playlistFile.existsSync()) {
        final content = playlistFile.readAsStringSync();
        if (content.contains('.ts')) break; // At least one segment is ready
      }
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (!playlistFile.existsSync()) {
      return Response.internalServerError(
        body: 'Timeout waiting for transcoder',
      );
    }

    return Response.ok(
      playlistFile.openRead(),
      headers: {
        'Content-Type': 'application/vnd.apple.mpegurl', // Correct HLS Mime
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache',
      },
    );
  });

  // Route: /api/vod/{streamId}/segment_{n}.ts (Serve segments)
  router.get('/<streamId>/<segment>',
      (Request request, String streamId, String segment) async {
    final file = File('${_hlsTempDir.path}/$streamId/$segment');

    if (!file.existsSync()) {
      return Response.notFound('Segment not found');
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'max-age=3600', // Cache segments
      },
    );
  });

  return router;
}

// ==========================================
// 3. RECORDING HANDLER (FFmpeg HLS Transcoding)
// ==========================================

Handler createRecordingStreamHandler(
  AppDatabase db, {
  bool Function()? isGpuEnabled,
}) {
  final router = Router();

  router.get('/<streamId>/playlist.m3u8', (Request request, String streamId) async {
    final recording = db.getRecordingById(streamId);
    if (recording == null || recording.filePath == null) {
      return Response.notFound('Recording or file not found');
    }

    final targetUrl = recording.filePath!;
    if (!File(targetUrl).existsSync()) {
      return Response.notFound('Physical recording file not found');
    }

    final streamDir = Directory('${_hlsTempDir.path}/rec_$streamId');

    if (_vodProcesses.containsKey('rec_$streamId')) {
      final existingProcess = _vodProcesses['rec_$streamId']!;
      final playlistFile = File('${streamDir.path}/playlist.m3u8');
      
      if (playlistFile.existsSync() && playlistFile.readAsStringSync().contains('.ts')) {
        return Response.ok(
          playlistFile.openRead(),
          headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'no-cache',
          },
        );
      }
      
      try { existingProcess.kill(); } catch (_) {}
      _vodProcesses.remove('rec_$streamId');
      if (streamDir.existsSync()) streamDir.deleteSync(recursive: true);
    }

    if (!_vodProcesses.containsKey('rec_$streamId')) {
      if (streamDir.existsSync()) streamDir.deleteSync(recursive: true);
      streamDir.createSync(recursive: true);

      final useNvidiaGpu = isGpuEnabled?.call() ?? _isNvidiaGpuEnabled();
      
      final ffmpegArgs = <String>[
        '-hide_banner', '-loglevel', 'warning',
        if (useNvidiaGpu) ...['-hwaccel', 'cuda'],
        '-i', targetUrl,
      ];

      if (useNvidiaGpu) {
        ffmpegArgs.addAll([
          '-c:v', 'h264_nvenc', '-preset', 'p4', '-tune', 'hq',
          '-rc', 'cbr', '-b:v', '3000k', '-maxrate', '3500k', '-bufsize', '6000k',
          '-g', '48', '-bf', '2', '-pix_fmt', 'yuv420p',
        ]);
      } else {
        ffmpegArgs.addAll([
          '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
          '-maxrate', '12000k', '-bufsize', '24000k', '-pix_fmt', 'yuv420p',
          '-g', '48', '-threads', '0',
        ]);
      }

      ffmpegArgs.addAll([
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
        '-af', 'pan=stereo|FL=1.0*FL+0.707*FC+0.5*BL+0.5*SL+0.5*LFE|FR=1.0*FR+0.707*FC+0.5*BR+0.5*SR+0.5*LFE,dynaudnorm=f=150:g=15',
        '-f', 'hls', '-hls_time', '4', '-hls_list_size', '0',
        '-hls_playlist_type', 'vod', '-hls_allow_cache', '1',
        '-hls_flags', 'independent_segments', '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', 'segment_%03d.ts', '-start_number', '0',
        'playlist.m3u8',
      ]);

      Process.start(_getFFmpegPath(), ffmpegArgs, workingDirectory: streamDir.path).then((process) {
        _vodProcesses['rec_$streamId'] = process;
        process.stderr.transform(utf8.decoder).listen((data) => print('[FFmpeg Rec $streamId] $data'));
        process.exitCode.then((code) {
          _vodProcesses.remove('rec_$streamId');
        });
      });
    }

    final playlistFile = File('${streamDir.path}/playlist.m3u8');
    int retries = 0;
    while (retries < 60) {
      if (playlistFile.existsSync() && playlistFile.readAsStringSync().contains('.ts')) break;
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (!playlistFile.existsSync()) return Response.internalServerError(body: 'Timeout waiting for transcoder');

    return Response.ok(
      playlistFile.openRead(),
      headers: {
        'Content-Type': 'application/vnd.apple.mpegurl',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache',
      },
    );
  });

  router.get('/<streamId>/<segment>', (Request request, String streamId, String segment) async {
    final file = File('${_hlsTempDir.path}/rec_$streamId/$segment');
    if (!file.existsSync()) return Response.notFound('Segment not found');
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'max-age=3600',
      },
    );
  });

  return router;
}
