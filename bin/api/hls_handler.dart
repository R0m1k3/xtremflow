import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Active FFmpeg processes and their temp directories
final Map<String, Process> _activeStreams = {};
final Map<String, Directory> _streamDirs = {};

/// Create handler for  HLS file serving
/// 
/// Serves playlist.m3u8 and segment files created by FFmpeg
Handler createHlsFileHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /api/hls/* requests
    if (!path.startsWith('api/hls/')) {
      return Response.notFound('Not found');
    }

    try {
      // Parse path: /api/hls/{streamId}/{filename}
      final pathParts = path.split('/');
      if (pathParts.length < 4) {
        return Response.badRequest(body: 'Invalid HLS path');
      }

      final streamId = pathParts[2];
      final filename = pathParts[3];

      // Get temp directory for this stream
      final tempDir = Directory('${Directory.systemTemp.path}/hls_$streamId');
      
      if (!await tempDir.exists()) {
        return Response.notFound('Stream not found');
      }

      // Construct file path
      final filePath = '${tempDir.path}/$filename';
      final file = File(filePath);

      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      // Determine content type
      String contentType;
      if (filename.endsWith('.m3u8')) {
        contentType = 'application/vnd.apple.mpegurl';
      } else if (filename.endsWith('.ts')) {
        contentType = 'video/MP2T';
      } else {
        contentType = 'application/octet-stream';
      }

      // Read and return file
      final fileBytes = await file.readAsBytes();
      
      return Response.ok(
        fileBytes,
        headers: {
          'Content-Type': contentType,
           'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      );

    } catch (e, stackTrace) {
      print('HLS file serving error: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'File serving error', 'message': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  };
}

/// Create handler for FFmpeg HLS transcoding
/// 
/// Starts FFmpeg process that creates HLS segments for VOD
Handler createStreamInitHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /api/stream/* requests
    if (!path.startsWith('api/stream/')) {
      return Response.notFound('Not found');
    }

    try {
      // Extract stream ID
      final pathParts = path.split('/');
      if (pathParts.length < 3) {
        return Response.badRequest(body: 'Invalid stream path');
      }
      
      final streamId = pathParts[2];
      
      // Get parameters
      final iptvUrl = request.url.queryParameters['url'];
      final quality = request.url.queryParameters['quality'] ?? 'high';
      
      if (iptvUrl == null || iptvUrl.isEmpty) {
        return Response.badRequest(body: 'Missing url parameter');
      }

      print('Starting HLS Stream for ID: $streamId');
      print('Source: $iptvUrl');

      // Create temp directory for HLS segments
      final tempDir = Directory('${Directory.systemTemp.path}/hls_$streamId');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      _streamDirs[streamId] = tempDir;
      
      final playlistPath = '${tempDir.path}/playlist.m3u8';
      
      // FFmpeg HLS arguments
      final ffmpegArgs = <String>[
        '-hide_banner',
        '-loglevel', 'error',
        '-user_agent', 'VLC/3.0.18 LibVLC/3.0.18',
        '-headers', 'Accept: */*\r\nConnection: keep-alive\r\n',
        
        // Input resilience
        '-reconnect', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '10',
        '-rw_timeout', '15000000',
        
        '-analyzeduration', '10000000',
        '-probesize', '5000000',
        
        '-i', iptvUrl,
        
        // Output format: HLS
        '-f', 'hls',
        '-hls_time', '4', 
        '-hls_list_size', '0', // Keep all segments in playlist
        '-hls_playlist_type', 'event', // Allow appending new segments, keep old ones
        '-hls_segment_type', 'mpegts',
        '-hls_segment_filename', '${tempDir.path}/segment_%03d.ts',
      ];

      // Detect if this is likely a Live TV stream (TS format) vs VOD (MKV/MP4)
      final isLiveStream = iptvUrl.endsWith('.ts') || iptvUrl.contains('/live/');
      
      // Video encoding strategy:
      // - Live TV (.ts): Try to COPY video stream for maximum quality (no re-encoding loss)
      // - VOD (MKV/MP4): Transcode to ensure timestamp compatibility
      if (isLiveStream) {
        // LIVE TV: Copy video stream for best quality
        // Most IPTV live streams are already H.264 and browser-compatible
        ffmpegArgs.addAll([
          '-c:v', 'copy', // No re-encoding = best quality
        ]);
      } else {
        // VOD: Transcode to fix timestamp issues in MKV containers
        ffmpegArgs.addAll([
          '-c:v', 'libx264',
          '-preset', 'fast', // Better quality than ultrafast
          '-tune', 'film', // Better for movies/series
          '-profile:v', 'high', // High profile for better compression
          '-level', '4.1', // Supports 1080p60
          '-pix_fmt', 'yuv420p',
          '-g', '48', // 2s GOP
        ]);

        if (quality == 'low') {
          ffmpegArgs.addAll([
            '-vf', 'scale=-2:480',
            '-b:v', '1500k',
            '-maxrate', '1500k',
            '-bufsize', '3000k',
          ]);
        } else {
          // High quality (default) - 6Mbps for 1080p
          ffmpegArgs.addAll([
            '-b:v', '6000k',
            '-maxrate', '8000k',
            '-bufsize', '12000k',
            '-crf', '18', // High quality CRF
          ]);
        }
      }
      
      // Audio: Always transcode to AAC (browsers don't support AC3/DTS)
      // Higher bitrate for better audio quality
      ffmpegArgs.addAll([
        '-c:a', 'aac',
        '-b:a', '192k', // Higher audio bitrate
        '-ar', '48000', // Standard sample rate
        '-ac', '2',
        
        playlistPath,
      ]);

      // Start FFmpeg process
      final process = await Process.start('ffmpeg', ffmpegArgs);
      _activeStreams[streamId] = process;

      // Log stderr
      process.stderr.transform(utf8.decoder).listen((data) {
        if (data.contains('Error') || data.contains('error')) {
          print('FFmpeg Error [$streamId]: $data');
        }
      });

      // Wait for playlist creation
      var attempts = 0;
      while (!await File(playlistPath).exists() && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (!await File(playlistPath).exists()) {
        process.kill();
        _activeStreams.remove(streamId);
        _streamDirs.remove(streamId);
        await tempDir.delete(recursive: true);
        return Response.internalServerError(
          body: 'FFmpeg failed to create playlist',
        );
      }

      // CRITICAL: Wait for first segment to exist AND HAVE DATA > 5MB to be safe? 
      // No, 10KB is enough for header + some data
      attempts = 0;
      final firstSegment = File('${tempDir.path}/segment_000.ts');
      while (attempts < 100) {
        if (await firstSegment.exists()) {
          final len = await firstSegment.length();
          if (len > 10240) break; // Wait for > 10KB
        }
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (!await firstSegment.exists()) {
        print('Warning: First segment not created yet for $streamId');
      } else {
        print('First segment ready for $streamId (${await firstSegment.length()} bytes)');
      }

      print('HLS playlist created for $streamId');

      // Cleanup on process exit
      process.exitCode.then((_) {
        print('FFmpeg finished for $streamId');
        _activeStreams.remove(streamId);
        final dir = _streamDirs.remove(streamId);
        dir?.delete(recursive: true).catchError((e) {
          print('Cleanup error for $streamId: $e');
        });
      });

      // Return playlist URL
      return Response.ok(
        jsonEncode({'playlist': '/api/hls/$streamId/playlist.m3u8'}),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );

    } catch (e, stackTrace) {
      print('Stream init error: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  };
}
