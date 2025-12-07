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
import '../../../core/models/iptv_models.dart';
import '../../../core/widgets/themed_loading_screen.dart';

/// Stream type enum for player
enum StreamType { live, vod, series }

/// Video player screen using FFmpeg transcoding for live streams
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String containerExtension;
  final PlaylistConfig playlist;
  final List<Channel>? channels;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
    this.channels,
    this.initialIndex = 0,
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
  late int _currentIndex;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _showControls = false;
  Timer? _controlsTimer;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _viewId = 'iptv-player-${widget.streamId}-${DateTime.now().millisecondsSinceEpoch}';
    
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
            ref.read(playbackPositionsProvider.notifier).clearPosition(_contentId);
          } else if (type == 'user_activity') {
            _onHover();
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
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _hideControls() {
    if (!mounted) return;
    setState(() {
      _showControls = false;
    });
  }

  void _onHover() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), _hideControls);
  }

  void _playNext() {
    if (widget.channels == null || widget.channels!.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % widget.channels!.length;
    _switchChannel(nextIndex);
  }

  void _playPrevious() {
    if (widget.channels == null || widget.channels!.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + widget.channels!.length) % widget.channels!.length;
    _switchChannel(prevIndex);
  }

  void _switchChannel(int index) {
    setState(() {
      _currentIndex = index;
      _isLoading = true;
      _isInitialized = false;
      _errorMessage = null;
    });
    // Give UI a moment to clear before re-initializing
    Future.microtask(() => _initializePlayer());
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
      
      // Determine effective Stream ID (from navigation or initial)
      final currentStreamId = widget.channels != null && widget.channels!.isNotEmpty
          ? widget.channels![_currentIndex].streamId 
          : widget.streamId;

      // Set content ID for resume features
      _contentId = widget.streamType == StreamType.live 
          ? '' 
          : '${widget.streamType.name}_$currentStreamId';

      String hlsUrl;
      
      if (widget.streamType == StreamType.live) {
        // For live streams, use FFmpeg transcoding
        setState(() {
          _statusMessage = 'Starting stream transcoding...';
        });
        
        // Build the FFmpeg endpoint URL with streaming settings
        final settings = ref.read(iptvSettingsProvider);
        final baseUrl = html.window.location.origin;
        final iptvUrl = '${widget.playlist.dns}/live/${widget.playlist.username}/${widget.playlist.password}/$currentStreamId.ts';
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
        
        // Construct the stream URL directly using MPEG-TS format
        final streamEndpoint = '$baseUrl/api/stream/$currentStreamId?url=$encodedUrl&quality=$qualityParam&buffer=$bufferParam&timeout=$timeoutParam&mode=$modeParam&ext=.ts';
        
        debugPrint('PlayerScreen: Starting Direct Stream: $streamEndpoint');
        hlsUrl = streamEndpoint;
        
      } else {
        // For VOD and Series - use direct proxy streaming with Range support
        final streamUrl = widget.streamType == StreamType.vod
            ? xtreamService.getVodStreamUrl(currentStreamId, widget.containerExtension)
            : xtreamService.getSeriesStreamUrl(currentStreamId, widget.containerExtension);
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
            ..style.height = '100%'
            ..allow = 'autoplay; fullscreen; picture-in-picture';
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
      appBar: _showControls ? AppBar(
        title: Text(widget.channels != null && widget.channels!.isNotEmpty 
            ? widget.channels![_currentIndex].name 
            : widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ) : null,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _onHover(),
        child: _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Failed to load stream', style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
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
                ? const ThemedLoading()
                : !_isInitialized
                    ? const ThemedLoading()
                    : Stack(
                        children: [
                          // HTML5 video player via iframe
                          HtmlElementView(viewType: _viewId),
                          
                          // Hover Controls Layer
                          if (_showControls) ...[
                            // Previous Channel (Left Zone)
                            if (widget.channels != null && widget.channels!.isNotEmpty)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: 100,
                                child: InkWell(
                                  onTap: _playPrevious,
                                  hoverColor: Colors.black12,
                                  child: const Center(
                                    child: Icon(Icons.arrow_back_ios, color: Colors.white, size: 48),
                                  ),
                                ),
                              ),

                            // Next Channel (Right Zone)
                            if (widget.channels != null && widget.channels!.isNotEmpty)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                width: 100,
                                child: InkWell(
                                  onTap: _playNext,
                                  hoverColor: Colors.black12,
                                  child: const Center(
                                    child: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 48),
                                  ),
                                ),
                              ),
                              
                            // EPG Overlay
                            if (widget.streamType == StreamType.live)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Colors.black87, Colors.transparent],
                                    ),
                                  ),
                                  child: EpgOverlay(
                                    streamId: widget.channels != null 
                                        ? widget.channels![_currentIndex].streamId
                                        : widget.streamId,
                                    playlist: widget.playlist,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
      ),
    );
  }
}
