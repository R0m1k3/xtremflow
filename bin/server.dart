import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:args/args.dart';
import 'database/database.dart';
import 'api/auth_handler.dart';
import 'api/playlists_handler.dart';
import 'middleware/auth_middleware.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8089')
    ..addOption('path', defaultsTo: '/app/web');
  
  final result = parser.parse(args);
  final port = int.parse(result['port']);
  final webPath = result['path'];

  // Initialize database
  final db = AppDatabase();
  await db.init();
  await db.seedAdmin();

  // Create API handlers
  final authHandler = AuthHandler(db);
  final playlistsHandler = PlaylistsHandler(db);

  // Setup router
  final apiRouter = Router()
    // Auth endpoints (no auth middleware) - full path including /api/
    ..mount('/api/auth', authHandler.router)
    // Playlists endpoints (with auth middleware)
    ..mount('/api/playlists', Pipeline()
      .addMiddleware(authMiddleware(db))
      .addHandler(playlistsHandler.router.call));

  // Create handlers
  final staticHandler = createStaticHandler(
    webPath,
    defaultDocument: 'index.html',
    listDirectories: false,
  );

  // Main handler with API proxy and FFmpeg streaming
  final handler = Cascade()
    .add(_createApiHandler(apiRouter))
    .add(_createStreamHandler())  // FFmpeg streaming endpoint
    .add(_createXtreamProxyHandler())
    .add(_createHlsHandler())  // Serve generated HLS files
    .add(staticHandler)
    .handler;

  // Add middleware
  final pipeline = Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(_corsMiddleware())
    .addHandler(handler);

  // Start server
  final server = await shelf_io.serve(
    pipeline,
    InternetAddress.anyIPv4,
    port,
  );

  print('Server started on port ${server.port}');
  print('Serving static files from: $webPath');
  print('REST API available at: /api/auth/* and /api/playlists/*');
  print('Xtream proxy available at: /api/xtream/*');
  print('FFmpeg streaming available at: /api/stream/*');
  
  // Clean expired sessions periodically (every hour)
  Timer.periodic(const Duration(hours: 1), (_) {
    db.cleanExpiredSessions();
    print('Cleaned expired sessions');
  });
}

/// Create API handler
Handler _createApiHandler(Router apiRouter) {
  return (Request request) async {
    final path = request.url.path;
    
    // Only handle /api/* requests (excluding /api/xtream)
    if (path.startsWith('api/') && !path.startsWith('api/xtream/')) {
      return apiRouter(request);
    }
    
    return Response.notFound('Not found');
  };
}

/// CORS middleware to allow cross-origin requests
Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      // Process request and add CORS headers to response
      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

final _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
};

/// Create Xtream proxy handler with M3U8 URL rewriting support
Handler _createXtreamProxyHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /api/xtream/* requests
    if (!path.startsWith('api/xtream/')) {
      return Response.notFound('Not found');
    }

    try {
      // Extract target URL from request
      // Format: /api/xtream/http://server:port/path
      // Note: URL might be URL-encoded (e.g., http%3A%2F%2F...)
      String apiPath = path.substring('api/xtream/'.length);
      
      // Decode URL if it's encoded (http%3A%2F%2F -> http://)
      if (apiPath.startsWith('http%3A') || apiPath.startsWith('https%3A')) {
        apiPath = Uri.decodeComponent(apiPath);
      }
      
      // The client will send the full URL after /api/xtream/
      if (!apiPath.startsWith('http://') && !apiPath.startsWith('https://')) {
        return Response.badRequest(
          body: 'Invalid API URL. Expected format: /api/xtream/http://...',
        );
      }

      // Reconstruct the full target URL with query parameters
      String fullUrl = apiPath;
      if (request.url.query.isNotEmpty) {
        // If the target URL already has query params, append with &
        if (fullUrl.contains('?')) {
          fullUrl = '$fullUrl&${request.url.query}';
        } else {
          fullUrl = '$fullUrl?${request.url.query}';
        }
      }
      
      final targetUrl = Uri.parse(fullUrl);
      final baseUrl = '${targetUrl.scheme}://${targetUrl.host}${targetUrl.hasPort ? ':${targetUrl.port}' : ''}';
      
      // Check if this is a video file that needs streaming
      final lowerPath = targetUrl.path.toLowerCase();
      final isVideoFile = lowerPath.endsWith('.mp4') || 
                          lowerPath.endsWith('.mkv') || 
                          lowerPath.endsWith('.avi') ||
                          lowerPath.endsWith('.ts') ||
                          lowerPath.endsWith('.m4v') ||
                          lowerPath.contains('/movie/') ||
                          lowerPath.contains('/series/');

      print('Proxying request to: $targetUrl (video streaming: $isVideoFile)');

      // For video files, use streaming with Range support for seeking
      if (isVideoFile) {
        final rangeHeader = request.headers['range'];
        return _streamVideoFile(targetUrl, rangeHeader);
      }

      // Headers to simulate a legitimate IPTV client (VLC/Kodi style)
      final proxyHeaders = {
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
        'Icy-MetaData': '1',
      };

      // Use simple http.get/post for non-video content
      http.Response response;
      if (request.method == 'GET') {
        response = await http.get(targetUrl, headers: proxyHeaders).timeout(
          const Duration(seconds: 30),
          onTimeout: () => http.Response('Request timeout', 504),
        );
      } else if (request.method == 'POST') {
        final body = await request.readAsString();
        response = await http.post(targetUrl, headers: proxyHeaders, body: body).timeout(
          const Duration(seconds: 30),
          onTimeout: () => http.Response('Request timeout', 504),
        );
      } else {
        return Response(405, body: 'Method not allowed');
      }

      // Check if this is an M3U8/HLS playlist that needs URL rewriting
      final contentType = response.headers['content-type'] ?? '';
      final isM3u8 = fullUrl.endsWith('.m3u8') || 
                     contentType.contains('application/vnd.apple.mpegurl') ||
                     contentType.contains('application/x-mpegurl') ||
                     contentType.contains('audio/mpegurl');

      if (isM3u8 && response.statusCode == 200) {
        // Rewrite URLs in M3U8 playlist to go through proxy
        final rewrittenBody = _rewriteM3u8Urls(
          response.body, 
          baseUrl, 
          targetUrl.path,
          request.requestedUri.origin,
        );
        
        print('Rewrote M3U8 playlist URLs for: $targetUrl');
        
        return Response(
          response.statusCode,
          body: rewrittenBody,
          headers: {
            'content-type': 'application/vnd.apple.mpegurl',
            'access-control-allow-origin': '*',
          },
        );
      }

      return Response(
        response.statusCode,
        body: response.bodyBytes,
        headers: {
          'content-type': response.headers['content-type'] ?? 'application/json',
          'access-control-allow-origin': '*',
        },
      );
    } catch (e, stackTrace) {
      print('Proxy error: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Proxy error', 'message': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  };
}

/// Stream video file using HttpClient with Range support for seeking
Future<Response> _streamVideoFile(Uri targetUrl, String? rangeHeader) async {
  try {
    final client = HttpClient();
    // Increase timeouts for large video files
    client.connectionTimeout = const Duration(seconds: 60);
    client.idleTimeout = const Duration(minutes: 5);  // Keep connection alive longer
    
    final req = await client.getUrl(targetUrl);
    req.headers.set('User-Agent', 'VLC/3.0.18 LibVLC/3.0.18');
    req.headers.set('Accept', '*/*');
    req.headers.set('Connection', 'keep-alive');
    req.headers.set('Accept-Encoding', 'identity');  // Don't compress video
    
    // Forward the Range header for seeking support
    if (rangeHeader != null && rangeHeader.isNotEmpty) {
      req.headers.set('Range', rangeHeader);
      print('Video streaming with Range: $rangeHeader');
    }
    
    final response = await req.close();
    
    // Get content type from response
    final contentType = response.headers.contentType?.mimeType ?? 'video/mp4';
    
    // Build response headers for optimal streaming/buffering
    final responseHeaders = <String, String>{
      'content-type': contentType,
      'access-control-allow-origin': '*',
      'accept-ranges': 'bytes',
      'cache-control': 'no-cache',  // Allow browser to cache but revalidate
      'connection': 'keep-alive',
    };
    
    // Add Content-Length if available (critical for seeking)
    if (response.contentLength > 0) {
      responseHeaders['content-length'] = response.contentLength.toString();
    }
    
    // Add Content-Range if this is a partial response (206)
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      responseHeaders['content-range'] = contentRange;
    }
    
    // Return appropriate status code (200 for full, 206 for partial)
    return Response(
      response.statusCode,
      body: response,
      headers: responseHeaders,
    );
  } catch (e) {
    print('Video streaming error: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Video streaming error', 'message': e.toString()}),
      headers: {'content-type': 'application/json'},
    );
  }
}

/// Rewrite URLs in M3U8 playlist to go through the proxy
/// 
/// Handles both relative and absolute URLs in HLS playlists
String _rewriteM3u8Urls(String m3u8Content, String baseUrl, String originalPath, String proxyOrigin) {
  final lines = m3u8Content.split('\n');
  final rewrittenLines = <String>[];
  
  // Get directory path for relative URL resolution
  final pathSegments = originalPath.split('/');
  pathSegments.removeLast(); // Remove filename
  final basePath = pathSegments.join('/');
  
  for (final line in lines) {
    final trimmedLine = line.trim();
    
    // Skip empty lines and comments (except URI in comments)
    if (trimmedLine.isEmpty) {
      rewrittenLines.add(line);
      continue;
    }
    
    // Handle lines that contain URLs (not starting with #, or EXT-X-KEY/EXT-X-MAP with URI)
    if (!trimmedLine.startsWith('#')) {
      // This is a segment URL
      final rewrittenUrl = _rewriteUrl(trimmedLine, baseUrl, basePath, proxyOrigin);
      rewrittenLines.add(rewrittenUrl);
    } else if (trimmedLine.contains('URI="')) {
      // Handle EXT-X-KEY, EXT-X-MAP, etc. with URI attribute
      final rewrittenLine = trimmedLine.replaceAllMapped(
        RegExp(r'URI="([^"]+)"'),
        (match) {
          final uri = match.group(1)!;
          final rewrittenUri = _rewriteUrl(uri, baseUrl, basePath, proxyOrigin);
          return 'URI="$rewrittenUri"';
        },
      );
      rewrittenLines.add(rewrittenLine);
    } else {
      rewrittenLines.add(line);
    }
  }
  
  return rewrittenLines.join('\n');
}

/// Rewrite a single URL to go through the proxy
String _rewriteUrl(String url, String baseUrl, String basePath, String proxyOrigin) {
  String fullUrl;
  
  if (url.startsWith('http://') || url.startsWith('https://')) {
    // Already absolute URL
    fullUrl = url;
  } else if (url.startsWith('/')) {
    // Absolute path, relative to server root
    fullUrl = '$baseUrl$url';
  } else {
    // Relative path, relative to current directory
    fullUrl = '$baseUrl$basePath/$url';
  }
  
  // Wrap with proxy
  return '$proxyOrigin/api/xtream/$fullUrl';
}

// ============================================
// FFmpeg Stream Transcoding Handler
// ============================================

/// Active FFmpeg processes by stream ID
final Map<String, Process> _activeStreams = {};

/// Create handler for FFmpeg streaming
/// 
/// This endpoint starts an FFmpeg process that connects to the IPTV server
/// with proper headers and transcodes the stream to local HLS files.
Handler _createStreamHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /api/stream/* requests
    if (!path.startsWith('api/stream/')) {
      return Response.notFound('Not found');
    }

    try {
      // Extract stream ID from path: /api/stream/{id}
      final pathParts = path.split('/');
      if (pathParts.length < 3) {
        return Response.badRequest(body: 'Invalid stream path');
      }
      
      final streamId = pathParts[2];
      
      // Get the IPTV URL from query parameter
      final iptvUrl = request.url.queryParameters['url'];
      if (iptvUrl == null || iptvUrl.isEmpty) {
        return Response.badRequest(body: 'Missing url parameter');
      }

      // Get streaming settings from query parameters
      final quality = request.url.queryParameters['quality'] ?? 'medium';
      final buffer = request.url.queryParameters['buffer'] ?? 'medium';
      final timeout = request.url.queryParameters['timeout'] ?? 'medium';
      final mode = request.url.queryParameters['mode'] ?? 'auto'; // direct, transcode, auto

      // Map quality to bitrate/CRF
      final (int bitrate, int crf) = switch (quality) {
        'low' => (1500, 26),
        'high' => (5000, 20),
        _ => (3000, 23), // medium
      };

      // Map buffer to segment duration and buffer size
      final (int segmentDuration, int bufferSize) = switch (buffer) {
        'low' => (2, 4000),
        'high' => (6, 12000),
        _ => (4, 8000), // medium
      };

      // Map timeout to seconds
      final int timeoutSeconds = switch (timeout) {
        'short' => 15,
        'long' => 60,
        _ => 30, // medium
      };

      print('Starting FFmpeg stream for ID: $streamId (quality=$quality, buffer=$buffer)');
      print('IPTV URL: $iptvUrl');

      // Create output directory for this stream
      final outputDir = Directory('/tmp/streams/$streamId');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Clean old files
      await for (final file in outputDir.list()) {
        await file.delete();
      }

      final outputPath = '${outputDir.path}/stream.m3u8';

      // Kill existing FFmpeg process for this stream if any
      if (_activeStreams.containsKey(streamId)) {
        _activeStreams[streamId]?.kill();
        _activeStreams.remove(streamId);
      }

      // Start FFmpeg process with VLC User-Agent
      // Transcode to H.264/AAC for browser compatibility (HEVC not supported in Chrome)
      // Using fast preset for lower CPU usage
      // Added resilience flags for corrupted/discontinuous streams
      //
      // Check if this is a VOD (file) or live stream
      final isVod = streamId.startsWith('vod_');
      
      final ffmpegArgs = <String>[
        '-y',  // Overwrite output files
        '-loglevel', 'warning',  // Reduce verbose output
        '-err_detect', 'ignore_err',  // Ignore decoding errors
        '-fflags', '+genpts+discardcorrupt+nobuffer',  // Generate PTS, discard corrupt, reduce buffering
        '-flags', 'low_delay',  // Low delay mode
        '-thread_queue_size', '4096',  // Prevent queue overflow on slow CPU
        '-analyzeduration', isVod ? '10000000' : '1000000',  // 10s for VOD, 1s for live (faster start)
        '-probesize', isVod ? '5000000' : '500000',  // 5MB for VOD, 500KB for live (faster start)
        '-user_agent', 'VLC/3.0.18 LibVLC/3.0.18',
        '-headers', 'Accept: */*\r\nConnection: keep-alive\r\n',
      ];
      
      // Add reconnect flags only for live streams (not VOD)
      if (!isVod) {
        ffmpegArgs.addAll([
          '-reconnect', '1',
          '-reconnect_streamed', '1',
          '-reconnect_delay_max', '5',
          '-reconnect_on_network_error', '1',
          '-reconnect_on_http_error', '4xx,5xx',
        ]);
      }
      
      ffmpegArgs.addAll(['-i', iptvUrl]);

      // Check mode: direct (copy) vs transcode
      final usePassthrough = mode == 'direct';
      
      if (usePassthrough) {
        // PASSTHROUGH MODE: Copy streams without re-encoding (0% CPU)
        // Only works if source is H.264/AAC compatible with browsers
        ffmpegArgs.addAll([
          '-c:v', 'copy',  // Copy video stream as-is
          '-c:a', 'copy',  // Copy audio stream as-is
          '-bsf:v', 'h264_mp4toannexb',  // Convert to Annex B format for HLS
        ]);
      } else {
        // TRANSCODE MODE: Re-encode for browser compatibility
        ffmpegArgs.addAll([
          // Video: transcode to H.264 for browser compatibility
          '-c:v', 'libx264',
          '-preset', 'ultrafast',  // Fastest encoding, lowest CPU (was: veryfast)
          '-tune', 'zerolatency',  // Low latency for live streaming
          '-profile:v', 'main',  // Main profile for better quality HD
          '-level', '4.0',  // Higher level for HD content
          '-pix_fmt', 'yuv420p',  // Required for browser compatibility
          '-crf', '$crf',  // Quality-based encoding from settings
          '-b:v', '${bitrate}k',  // Video bitrate from settings
          '-maxrate', '${(bitrate * 1.5).round()}k',  // Allow larger bursts
          '-bufsize', '${bufferSize}k',  // Buffer size from settings
        ]);
      }
      
      // Add timestamp handling for live streams
      if (!isVod) {
        ffmpegArgs.addAll([
          '-fps_mode', 'passthrough',  // Pass through timestamps as-is
        ]);
      } else {
        ffmpegArgs.addAll([
          '-fps_mode', 'cfr',  // Constant frame rate for VOD
          '-g', '48',  // Keyframe every 2 seconds at 24fps
          '-keyint_min', '48',
        ]);
      }
      
      // Audio handling for transcode mode
      if (!usePassthrough) {
        ffmpegArgs.addAll([
          '-c:a', 'aac',
          '-b:a', '128k',
          '-ar', '44100',
          '-ac', '2',  // Force stereo
        ]);
      }
      
      ffmpegArgs.addAll([
        '-avoid_negative_ts', 'make_zero',  // Handle negative timestamps
        '-max_muxing_queue_size', '1024',  // Prevent queue overflow
        // HLS output settings - optimized for stability
        '-f', 'hls',
        '-hls_time', isVod ? '4' : '$segmentDuration',  // Segment duration from settings for live
        '-hls_list_size', isVod ? '0' : '20',  // Keep all segments for VOD, 20 for live (was 10)
        '-hls_flags', isVod ? 'independent_segments' : 'append_list+omit_endlist+program_date_time',  // Removed delete_segments to avoid 404s
        '-hls_delete_threshold', '5',  // Keep 5 extra segments before deleting
        '-hls_start_number_source', 'datetime',  // Better segment continuity
        '-hls_segment_filename', '${outputDir.path}/segment_%d.ts',
        outputPath,
      ]);

      final process = await Process.start('ffmpeg', ffmpegArgs);

      _activeStreams[streamId] = process;

      // Collect FFmpeg stderr for error reporting
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);
        // Print warnings and errors
        if (data.contains('Error') || data.contains('error') || data.contains('Warning')) {
          print('FFmpeg [$streamId]: $data');
        }
      });

      process.exitCode.then((code) {
        print('FFmpeg process [$streamId] exited with code: $code');
        if (code != 0) {
          print('FFmpeg stderr: ${stderrBuffer.toString().substring(0, stderrBuffer.length.clamp(0, 500))}');
        }
        _activeStreams.remove(streamId);
      });

      // Wait for FFmpeg to create the initial playlist (transcoding takes longer)
      await Future.delayed(const Duration(seconds: 5));

      // Check if stream started successfully
      final playlistFile = File(outputPath);
      if (!await playlistFile.exists()) {
        // FFmpeg failed - get error message
        final stderr = stderrBuffer.toString();
        print('FFmpeg failed to create playlist for $streamId');
        print('FFmpeg stderr: $stderr');
        process.kill();
        _activeStreams.remove(streamId);
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'FFmpeg failed to start stream',
            'details': stderr.length > 200 ? stderr.substring(0, 200) : stderr,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Return the local HLS URL
      return Response.ok(
        jsonEncode({
          'status': 'started',
          'streamId': streamId,
          'hlsUrl': '/hls/$streamId/stream.m3u8',
        }),
        headers: {
          'content-type': 'application/json',
          'access-control-allow-origin': '*',
        },
      );
    } catch (e, stackTrace) {
      print('Stream error: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Stream error', 'message': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  };
}

/// Create handler for serving HLS files generated by FFmpeg
Handler _createHlsHandler() {
  return (Request request) async {
    final path = request.url.path;

    // Only handle /hls/* requests
    if (!path.startsWith('hls/')) {
      return Response.notFound('Not found');
    }

    try {
      // Extract file path: /hls/{streamId}/{filename}
      final relativePath = path.substring('hls/'.length);
      final filePath = '/tmp/streams/$relativePath';
      
      final file = File(filePath);
      if (!await file.exists()) {
        return Response.notFound('HLS file not found');
      }

      // Determine content type
      String contentType;
      if (filePath.endsWith('.m3u8')) {
        contentType = 'application/vnd.apple.mpegurl';
      } else if (filePath.endsWith('.ts')) {
        contentType = 'video/MP2T';
      } else {
        contentType = 'application/octet-stream';
      }

      final bytes = await file.readAsBytes();
      
      return Response.ok(
        bytes,
        headers: {
          'content-type': contentType,
          'access-control-allow-origin': '*',
          'cache-control': 'no-cache',
        },
      );
    } catch (e) {
      print('HLS serve error: $e');
      return Response.internalServerError(body: 'Error serving HLS file');
    }
  };
}
