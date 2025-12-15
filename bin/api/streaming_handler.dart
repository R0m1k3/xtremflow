import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import '../../lib/core/models/playlist_config.dart';

/// Active FFmpeg processes for VOD transcoding
final Map<String, Process> _vodProcesses = {};

/// Directory for temporary HLS segments
final Directory _hlsTempDir = Directory('/tmp/hls_vod');

/// Initialize streaming subsystem
Future<void> initStreaming() async {
  if (!_hlsTempDir.existsSync()) {
    await _hlsTempDir.create(recursive: true);
  }
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

Handler createLiveStreamHandler(Future<PlaylistConfig?> Function(Request) getPlaylist) {
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
    
    final targetUrl = Uri.parse('${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts');
    print('[Live] Proxying: $targetUrl');

    final client = http.Client();
    final streamRequest = http.Request('GET', targetUrl);
    
    // Spoof User-Agent to avoid 403/405 from providers
    streamRequest.headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18'; 
    streamRequest.headers['Connection'] = 'keep-alive';
    
    try {
      final streamResponse = await client.send(streamRequest);
      print('[Live] Upstream response: ${streamResponse.statusCode} ${streamResponse.reasonPhrase}');

      // Filter headers to avoid encoding issues with shelf
      final responseHeaders = Map<String, Object>.from(streamResponse.headers);
      responseHeaders.remove('content-length');
      responseHeaders.remove('content-encoding');
      responseHeaders.remove('transfer-encoding');

      return Response(
        streamResponse.statusCode,
        body: streamResponse.stream,
        headers: responseHeaders,
      );
    } catch (e) {
      print('[Live] Upstream connection error: $e');
      return Response.internalServerError(body: 'Upstream error: $e');
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

Handler createVodStreamHandler(Future<PlaylistConfig?> Function(Request) getPlaylist) {
  final router = Router();

  // Route: /api/vod/{streamId}/playlist.m3u8
  router.get('/<streamId>/playlist.m3u8', (Request request, String streamId) async {
    final playlist = await getPlaylist(request);
    if (playlist == null) return Response.internalServerError(body: 'No playlist');

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
          print('[VOD] Reusing existing session for $streamId');
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


    // Build Upstream URL (Try MKV first, then generic)
    // Note: We don't know the extension here easily unless passed. 
    // Xtream usually allows access via streamId.mkv or streamId.mp4 regardless of actual file
    // We'll trust the ID.
    // Only start FFmpeg if not already running
    if (!_vodProcesses.containsKey(streamId)) {
       // Prepare directory (Only for new session)
       if (streamDir.existsSync()) {
         streamDir.deleteSync(recursive: true);
       }
       streamDir.createSync(recursive: true);

       final targetUrl = '${playlist.dns}/movie/${playlist.username}/${playlist.password}/$streamId.mkv';
       print('[VOD] Starting Transcode: $targetUrl');

    // Start FFmpeg
    final ffmpegArgs = [
      '-hide_banner', '-loglevel', 'error',
      '-headers', 'User-Agent: VLC/3.0.18 LibVLC/3.0.18\r\n',
      '-i', targetUrl,
      
      // Video: H.264 Ultrafast (Low CPU)
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-tune', 'fastdecode',
      '-crf', '23',
      '-maxrate', '3000k',
      '-bufsize', '6000k',
      '-pix_fmt', 'yuv420p',
      '-threads', '0',

      // Audio: AAC (Browser compatible, improved quality)
      '-c:a', 'aac',
      '-b:a', '192k',      // Higher bitrate for better quality
      '-ar', '48000',      // Standard sample rate
      '-ac', '2',

      '-f', 'hls',
      '-hls_time', '4',
      '-hls_list_size', '0', 
      '-hls_playlist_type', 'event', // Event type allows immediate playback while transcoding
      '-hls_allow_cache', '1',
      '-hls_segment_type', 'mpegts',
      '-hls_segment_filename', '${streamDir.path}/segment_%03d.ts',
      '-start_number', '0',
      
      // Write playlist to stdout or file? File is easier for static serving
      '${streamDir.path}/playlist.m3u8'
    ];

      Process.start('ffmpeg', ffmpegArgs).then((process) {
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

    // Wait for playlist to appear (max 10s)
    final playlistFile = File('${streamDir.path}/playlist.m3u8');
    int retries = 0;
    while (!playlistFile.existsSync() && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (!playlistFile.existsSync()) {
      return Response.internalServerError(body: 'Timeout waiting for transcoder');
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
  router.get('/<streamId>/<segment>', (Request request, String streamId, String segment) async {
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
