import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
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
    if (streamId.endsWith('.ts')) {
      streamId = streamId.substring(0, streamId.length - 3);
    }

    final playlist = await getPlaylist(request);
    
    // ... existing logic ...
    
    final targetUrl = Uri.parse('${playlist.dns}/live/${playlist.username}/${playlist.password}/$streamId.ts');
    print('[Live] Proxying: $targetUrl');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10); // Connection timeout
      client.idleTimeout = const Duration(hours: 6);          // Keep alive long time

      final req = await client.getUrl(targetUrl);
      req.headers.set('User-Agent', 'VLC/3.0.18 LibVLC/3.0.18'); // Simulate VLC
      req.headers.set('Connection', 'keep-alive');

      final response = await req.close();
      
      if (response.statusCode != 200) {
        return Response(response.statusCode, body: 'Upstream error: ${response.statusCode}');
      }

      print('[Live] Connected to upstream. Streaming...');

      // Pipe the response stream to the client
      // We use a StreamController to handle cancellation
      final controller = StreamController<List<int>>();
      
      response.listen(
        (data) => controller.add(data),
        onError: (e) => controller.addError(e),
        onDone: () => controller.close(),
        cancelOnError: true,
      );

      // Cleanup when client disconnects
      controller.onCancel = () {
        print('[Live] Client disconnected: $streamId');
        // response.detachSocket() if possible, or just let GC handle it
      };

      return Response.ok(
        controller.stream,
        headers: {
          'Content-Type': 'video/mp2t',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
          'Access-Control-Allow-Origin': '*',
        },
      );

    } catch (e) {
      print('[Live] Error: $e');
      return Response.internalServerError(body: 'Live stream error: $e');
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

    // Clean up old session if exists
    if (_vodProcesses.containsKey(streamId)) {
      print('[VOD] Killing previous session for $streamId');
      _vodProcesses[streamId]?.kill();
      _vodProcesses.remove(streamId);
    }
    
    // Prepare directory
    final streamDir = Directory('${_hlsTempDir.path}/$streamId');
    if (streamDir.existsSync()) {
      streamDir.deleteSync(recursive: true);
    }
    streamDir.createSync(recursive: true);

    // Build Upstream URL (Try MKV first, then generic)
    // Note: We don't know the extension here easily unless passed. 
    // Xtream usually allows access via streamId.mkv or streamId.mp4 regardless of actual file
    // We'll trust the ID.
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

      // Audio: AAC (Browser compatible)
      '-c:a', 'aac',
      '-b:a', '128k',
      '-ac', '2',

      // HLS Output options
      '-f', 'hls',
      '-hls_time', '4',
      '-hls_list_size', '0', // Keep all segments
      '-hls_segment_type', 'mpegts',
      '-hls_segment_filename', '${streamDir.path}/segment_%03d.ts',
      '-start_number', '0',
      
      // Write playlist to stdout or file? File is easier for static serving
      '${streamDir.path}/playlist.m3u8'
    ];

    Process.start('ffmpeg', ffmpegArgs).then((process) {
      _vodProcesses[streamId] = process;
      
      process.stderr.transform(utf8.decoder).listen((data) {
        if (data.contains('Error')) print('[FFmpeg $streamId] $data');
      });

      process.exitCode.then((code) {
        print('[VOD] FFmpeg exited with code $code');
        _vodProcesses.remove(streamId);
      });
    });

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
