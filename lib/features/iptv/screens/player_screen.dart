import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/epg_overlay.dart';
import '../../../core/models/playlist_config.dart';

/// Stream type enum for player
enum StreamType { live, vod, series }

/// Video player screen using FFmpeg transcoding for live streams
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String containerExtension;
  final PlaylistConfig playlist;

  const PlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  String? _hlsUrl;
  String? _errorMessage;
  String? _statusMessage;
  late String _viewId;
  late String _contentId;
  bool _isInitialized = false;
  bool _isLoading = true;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _viewId = 'iptv-player-${widget.streamId}-${DateTime.now().millisecondsSinceEpoch}';
    // Content ID for resume feature
    _contentId = widget.streamType == StreamType.live 
        ? '' // Live streams don't need resume
        : '${widget.streamType.name}_${widget.streamId}';
    _initializePlayer();
    _setupMessageListener();
  }

  void _setupMessageListener() {
    // Listen for postMessage from player.html iframe
    _messageSubscription = html.window.onMessage.listen((event) {
      try {
        final data = event.data;
        if (data is Map) {
          final type = data['type'];
          if (type == 'playback_position' && _contentId.isNotEmpty) {
            final currentTime = (data['currentTime'] as num).toDouble();
            final duration = (data['duration'] as num).toDouble();
            ref.read(playbackPositionsProvider.notifier).savePosition(
              _contentId, currentTime, duration
            );
          } else if (type == 'playback_ended' && _contentId.isNotEmpty) {
            // Clear position when video ends
            ref.read(playbackPositionsProvider.notifier).clearPosition(_contentId);
          }
        }
      } catch (e) {
        debugPrint('Error handling postMessage: $e');
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Validating playlist...';
      });

      // Validate playlist before proceeding
      if (widget.playlist.dns.isEmpty || 
          widget.playlist.username.isEmpty || 
          widget.playlist.password.isEmpty) {
        throw Exception('Invalid playlist configuration: missing credentials');
      }

      final xtreamService = ref.read(xtreamServiceProvider(widget.playlist));
      xtreamService.setPlaylist(widget.playlist);
      
      String hlsUrl;
      
      if (widget.streamType == StreamType.live) {
        // For live streams, use FFmpeg transcoding
        setState(() {
          _statusMessage = 'Starting stream transcoding...';
        });
        
        // Build the FFmpeg endpoint URL with streaming settings
        final settings = ref.read(iptvSettingsProvider);
        final baseUrl = html.window.location.origin;
        final iptvUrl = '${widget.playlist.dns}/live/${widget.playlist.username}/${widget.playlist.password}/${widget.streamId}.ts';
        final encodedUrl = Uri.encodeComponent(iptvUrl);
        
        // Map enum values to string params
        final qualityParam = switch (settings.streamQuality) {
          StreamQuality.low => 'low',
          StreamQuality.medium => 'medium',
          StreamQuality.high => 'high',
        };
        final bufferParam = switch (settings.bufferSize) {
          BufferSize.low => 'low',
          BufferSize.medium => 'medium',
          BufferSize.high => 'high',
        };
        final timeoutParam = switch (settings.connectionTimeout) {
          ConnectionTimeout.short => 'short',
          ConnectionTimeout.medium => 'medium',
          ConnectionTimeout.long => 'long',
        };
        final modeParam = settings.modeString; // direct, transcode, or auto
        
        final streamEndpoint = '$baseUrl/api/stream/${widget.streamId}?url=$encodedUrl&quality=$qualityParam&buffer=$bufferParam&timeout=$timeoutParam&mode=$modeParam';
        
        debugPrint('PlayerScreen: Starting FFmpeg stream: $streamEndpoint');
        
        // Call the FFmpeg streaming endpoint
        final response = await http.get(Uri.parse(streamEndpoint));
        
        if (response.statusCode != 200) {
          throw Exception('Failed to start stream: ${response.body}');
        }
        
        final data = jsonDecode(response.body);
        if (data['status'] != 'started') {
          throw Exception('Stream failed to start: ${data['error'] ?? 'Unknown error'}');
        }
        
        // Get the local HLS URL
        hlsUrl = '$baseUrl${data['hlsUrl']}';
        debugPrint('PlayerScreen: FFmpeg HLS URL: $hlsUrl');
        
      } else {
        // For VOD and Series - use direct proxy streaming with Range support
        // This allows seeking via HTTP Range requests
        final streamUrl = widget.streamType == StreamType.vod
            ? xtreamService.getVodStreamUrl(widget.streamId, widget.containerExtension)
            : xtreamService.getSeriesStreamUrl(widget.streamId, widget.containerExtension);
        hlsUrl = streamUrl;
        debugPrint('PlayerScreen: Direct playback URL: $hlsUrl');
      }
      
      setState(() {
        _statusMessage = 'Loading player...';
      });
      
      // Get resume position for VOD/Series
      double startTime = 0;
      if (widget.streamType != StreamType.live && _contentId.isNotEmpty) {
        final positions = ref.read(playbackPositionsProvider);
        startTime = positions.getPosition(_contentId);
        if (startTime > 0) {
          debugPrint('PlayerScreen: Resuming from ${startTime.toStringAsFixed(0)}s');
        }
      }
      
      // Register the HTML view with an iframe pointing to our player.html
      final encodedHlsUrl = Uri.encodeComponent(hlsUrl);
      final playerUrl = startTime > 0 
          ? 'player.html?url=$encodedHlsUrl&startTime=${startTime.toStringAsFixed(0)}'
          : 'player.html?url=$encodedHlsUrl';
      
      debugPrint('PlayerScreen: Player URL: $playerUrl');
      
      // Register platform view factory
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = playerUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allow = 'autoplay; fullscreen'
            ..allowFullscreen = true;
          return iframe;
        },
      );

      setState(() {
        _hlsUrl = hlsUrl;
        _isInitialized = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('PlayerScreen error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load stream',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _isLoading = true;
                      });
                      _initializePlayer();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage ?? 'Loading...',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                )
              : !_isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : Stack(
                      children: [
                        // HTML5 video player via iframe
                        HtmlElementView(viewType: _viewId),
                        // EPG overlay for live streams
                        if (widget.streamType == StreamType.live)
                          Positioned(
                            bottom: 80,
                            left: 0,
                            right: 0,
                            child: EpgOverlay(
                              streamId: widget.streamId,
                              playlist: widget.playlist,
                            ),
                          ),
                      ],
                    ),
    );
  }
}
