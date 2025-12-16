import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
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
    if (File('ffmpeg/bin/ffmpeg.exe').existsSync())
      return 'ffmpeg/bin/ffmpeg.exe';
  }
  return 'ffmpeg'; // Default to PATH
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
            const Duration(seconds: 10),
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

Handler createLiveStreamHandler(
    Future<PlaylistConfig?> Function(Request) getPlaylist) {
  final router = Router();

  // Route: /api/live/{streamId} (Catch all pattern to debug)
  router.get('/<streamId|.*>', (Request request, String streamId) async {
    print('[Live] Incoming request for streamId: $streamId');

    // Remove .ts extension if present
    // Remove extension if present (handle both .ts and .m3u8 just in case)
    if (streamId.endsWith('.ts')) {
      streamId = streamId.substring(0, streamId.length - 3);
    } else if (streamId.endsWith('.m3u8')) {
      streamId = streamId.substring(0, streamId.length - 5);
    }

    final playlist = await getPlaylist(request);

    if (playlist == null) {
      print('[Live] Error: No playlist found');
      return Response.internalServerError(body: 'No playlist configured');
    }

    // Use original URL - let FFmpeg handle HTTP redirects natively
    // Manual redirect resolution consumes one-time tokens from IPTV servers
    final targetUrl =
        '${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts';
    print('[Live] Streaming via FFmpeg: $targetUrl');

    // Start FFmpeg to proxy and stabilize the stream
    // We use "-c copy" to avoid transcoding (Low CPU) but gain FFmpeg's network robustness
    final ffmpegArgs = [
      '-hide_banner', '-loglevel', 'error',
      // Full headers to mimic a real video player
      '-headers',
      'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\nAccept: */*\r\nConnection: keep-alive\r\nReferer: ${playlist.dns}/\r\n',

      // HTTP redirect handling and robustness flags
      '-reconnect', '1',
      '-reconnect_at_eof', '1',
      '-reconnect_streamed', '1',
      '-reconnect_delay_max', '5',
      '-rw_timeout', '15000000',
      '-analyzeduration', '5000000', // Faster probe for live
      '-probesize', '5000000',
      '-max_reload', '3', // Allow up to 3 retries for failed requests

      '-i', targetUrl,

      '-c', 'copy', // Direct stream copy (Very low CPU)
      '-f', 'mpegts',
      'pipe:1', // Output to stdout
    ];

    try {
      final ffmpegPath = _getFFmpegPath();
      final process = await Process.start(ffmpegPath, ffmpegArgs);

      // Cleanup handling: Kill FFmpeg when client disconnects
      final controller = StreamController<List<int>>(
        onCancel: () {
          print('[Live] Client disconnected, killing FFmpeg for $streamId');
          process.kill();
        },
      );

      // Pipe stdout to controller
      process.stdout.listen(
        (data) => controller.add(data),
        onDone: () {
          print('[Live] FFmpeg stream ended for $streamId');
          controller.close();
        },
        onError: (e) {
          print('[Live] FFmpeg stream error: $e');
          controller.addError(e);
        },
      );

      // Log errors
      process.stderr.transform(utf8.decoder).listen((data) {
        print('[FFmpeg Live $streamId] $data');
      });

      return Response.ok(
        controller.stream,
        headers: {
          'Content-Type': 'video/mp2t',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache',
        },
      );
    } catch (e) {
      print('[Live] Failed to start FFmpeg: $e');
      return Response.internalServerError(body: 'Stream start error: $e');
    }
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
    Future<PlaylistConfig?> Function(Request) getPlaylist) {
  final router = Router();

  // Route: /api/vod/{streamId}/playlist.m3u8
  router.get('/<streamId>/playlist.m3u8',
      (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null)
      return Response.internalServerError(body: 'No playlist');

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

      // Start FFmpeg
      final ffmpegArgs = [
        '-hide_banner', '-loglevel', 'error',
        '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',

        // Robustness for network streams
        '-reconnect', '1',
        '-reconnect_at_eof', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '5',
        '-rw_timeout', '15000000',
        '-analyzeduration',
        '2000000', // Reduced from 10M to 2M for faster start
        '-probesize', '2000000', // Reduced from 10M to 2M for faster start

        '-i', targetUrl,

        // Video: H.264 Ultrafast (Low CPU)
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency', // Optimize for low latency startup
        '-tune', 'fastdecode',
        '-crf', '23',
        '-maxrate', '3000k',
        '-bufsize', '6000k',
        '-pix_fmt', 'yuv420p',
        '-threads', '0',

        // Audio: AAC (Browser compatible, improved quality)
        '-c:a', 'aac',
        '-b:a', '192k',
        '-ar', '48000',

        // Advanced Audio Filtering:
        // 1. "pan": Downmix 5.1/7.1 to Stereo with center mix (dialogue) boosted.
        // 2. "dynaudnorm": Dynamic Audio Normalizer to boost quiet dialogue and limit loud explosions (Night Mode effect).
        '-af',
        'pan=stereo|FL=1.0*FL+0.707*FC+0.5*BL+0.5*SL+0.5*LFE|FR=1.0*FR+0.707*FC+0.5*BR+0.5*SR+0.5*LFE,dynaudnorm=f=150:g=15',

        '-f', 'hls',
        '-hls_time', '4',
        '-hls_list_size', '0',
        '-hls_playlist_type',
        'event', // Event type allows immediate playback while transcoding
        '-hls_allow_cache', '1',
        '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', '${streamDir.path}/segment_%03d.ts',
        '-start_number', '0',

        // Write playlist to stdout or file? File is easier for static serving
        '${streamDir.path}/playlist.m3u8',
      ];

      final ffmpegPath = _getFFmpegPath();
      Process.start(ffmpegPath, ffmpegArgs).then((process) {
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

    // Wait for playlist to appear (max 30s)
    final playlistFile = File('${streamDir.path}/playlist.m3u8');
    int retries = 0;
    while (!playlistFile.existsSync() && retries < 60) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (!playlistFile.existsSync()) {
      return Response.internalServerError(
          body: 'Timeout waiting for transcoder');
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
