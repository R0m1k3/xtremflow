import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';

// ... (existing imports)
// ... (existing imports)
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/epg_overlay.dart';

enum StreamType { live, vod, series }

class PlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final PlaylistConfig playlist;
  final StreamType streamType;
  final String containerExtension;
  final List<Channel>? channels;
  final double? startTime;
  final Duration? duration;

  const PlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
    this.channels,
    this.startTime,
    this.duration,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _isPlaying = true;
  bool _showControls = false;
  Timer? _controlsTimer;
  double _currentPosition = 0;
  double _totalDuration = 1;
  int _currentIndex = 0;
  bool _isInitialized = false;
  bool _isLoading = true;
  StreamSubscription? _messageSubscription;
  final String _aspectRatio = 'contain';
  bool _isSeeking = false;
  String _viewId = 'iptv-player';
  String? _currentStreamUrl;
  String _statusMessage = 'Loading...';
  String? _errorMessage;
  bool _isMuted = false;
  bool _ignoreStatusUpdates = false;

  @override
  void initState() {
    super.initState();
    if (widget.channels != null) {
      _currentIndex =
          widget.channels!.indexWhere((c) => c.streamId == widget.streamId);
      if (_currentIndex == -1) _currentIndex = 0;
    }
    // Show controls at start, then auto-hide after timeout
    _showControls = true;
    _onHover(); // Start the auto-hide timer
    _initializePlayer(startTimeOverride: widget.startTime);
    _setupMessageListener();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _controlsTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializePlayer({
    double? startTimeOverride,
    bool isChannelSwitch = false,
  }) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading...';
    });

    try {
      // Determine Stream ID (Initial or Current Index)
      final currentStreamId = isChannelSwitch && widget.channels != null
          ? widget.channels![_currentIndex].streamId
          : widget.streamId;

      _viewId =
          'iptv-player-$currentStreamId-${DateTime.now().millisecondsSinceEpoch}';

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      String streamUrl = '';

      // Generate Stream URL based on type
      // NOTE: Logic is now handled by the backend routes /api/live/ and /api/vod/
      if (widget.streamType == StreamType.live) {
        streamUrl = service.getLiveStreamUrl(currentStreamId);
      } else if (widget.streamType == StreamType.vod) {
        streamUrl =
            service.getVodStreamUrl(currentStreamId, widget.containerExtension);
      } else if (widget.streamType == StreamType.series) {
        streamUrl = service.getSeriesStreamUrl(
          currentStreamId,
          widget.containerExtension,
        );
      }

      // Store URL for Lite Player
      _currentStreamUrl = streamUrl;

      final encodedUrl = Uri.encodeComponent(streamUrl);
      final streamTypeParam =
          widget.streamType == StreamType.live ? 'live' : 'vod';

      // Force player choice based on stream type:
      // - Live TV: Player Lite (simple TS playback with mpegts.js)
      // - VOD/Series: Player Standard (fuller controls, HLS support)
      final isLiveTV = widget.streamType == StreamType.live;
      // Cache buster to force reload of updated player.html
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;

      var playerSrc = isLiveTV
          ? 'player_lite.html?url=$encodedUrl&type=live&v=$cacheBuster'
          : 'player.html?url=$encodedUrl&type=vod&v=$cacheBuster';

      if (startTimeOverride != null) {
        playerSrc += '&t=$startTimeOverride';
      }

      if (widget.duration != null) {
        playerSrc += '&duration=${widget.duration!.inSeconds}';
      }

      // Register View Factory (Only needed for Standard Player, but safe to do always or conditionally)
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        final iframe = html.IFrameElement()
          ..id = _viewId
          ..src = playerSrc
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'autoplay; fullscreen; picture-in-picture; encrypted-media';
        return iframe;
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });

        // Force unmute on load (after a short delay to ensure iframe is ready)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _sendMessage({'type': 'set_volume', 'value': 1.0});
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load stream: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _setupMessageListener() {
    _messageSubscription = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data == null) return;

      final type = data['type'];
      if (type == 'playback_position') {
        final currentTime = (data['currentTime'] as num).toDouble();
        final rawDuration = (data['duration'] as num).toDouble();
        final duration = rawDuration.isFinite ? rawDuration : 0.0;

        // Only update position if user is NOT dragging the slider
        if (!_isSeeking) {
          setState(() {
            _currentPosition = currentTime;
            _totalDuration = duration > 0 ? duration : 1;
          });
        }

        // Update watch history if relevant
        if (currentTime > 0) {
          ref.read(playbackPositionsProvider.notifier).savePosition(
                widget.streamId,
                currentTime,
                duration,
              );
        }
      } else if (type == 'playback_status') {
        if (!_ignoreStatusUpdates) {
          setState(() => _isPlaying = data['status'] == 'playing');
        }
      } else if (type == 'user_activity') {
        _onHover();
      }
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (!_isInitialized) return;

    // Try finding by ID first
    var iframe = html.document.getElementById(_viewId) as html.IFrameElement?;

    // If not found, try finding by src pattern (fallback for Shadow DOM or ID issues)
    if (iframe == null) {
      final iframes = html.document.getElementsByTagName('iframe');
      for (final frame in iframes) {
        if (frame is html.IFrameElement &&
            (frame.src?.contains('player_lite.html') == true ||
                frame.src?.contains('player.html') == true)) {
          iframe = frame;
          break;
        }
      }
    }

    if (iframe != null) {
      print('[PlayerScreen] Sending message to iframe: $message');
      iframe.contentWindow?.postMessage(message, '*');
    } else {
      print(
          '[PlayerScreen] Error: Could not find iframe to send message: $message');
    }
  }

  void _onHover() {
    setState(() => _showControls = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _togglePlayPause() {
    // Optimistic update to make UI responsive immediately
    setState(() => _isPlaying = !_isPlaying);

    // Ignore incoming status updates for 2 seconds to prevent fighting
    _ignoreStatusUpdates = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _ignoreStatusUpdates = false;
    });

    if (_isPlaying) {
      _sendMessage({'type': 'play'});
    } else {
      _sendMessage({'type': 'pause'});
    }
  }

  void _toggleFullscreen() {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    } else {
      html.document.documentElement?.requestFullscreen();
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _sendMessage({'type': 'set_volume', 'value': _isMuted ? 0.0 : 1.0});
  }

  void _previousChannel() {
    if (widget.channels != null && widget.channels!.isNotEmpty) {
      setState(() {
        if (_currentIndex > 0) {
          _currentIndex--;
        } else {
          _currentIndex = widget.channels!.length - 1;
        }
      });
      _initializePlayer(isChannelSwitch: true);
    }
  }

  void _nextChannel() {
    if (widget.channels != null && widget.channels!.isNotEmpty) {
      setState(() {
        if (_currentIndex < widget.channels!.length - 1) {
          _currentIndex++;
        } else {
          _currentIndex = 0;
        }
      });
      _initializePlayer(isChannelSwitch: true);
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isLiveTV = widget.streamType == StreamType.live;

    // LITE PLAYER MODE for Live TV - Simplified UI (no BackdropFilter)
    if (isLiveTV) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video Player
            if (_isInitialized) HtmlElementView(viewType: _viewId),

            // Control Overlay (sits on top of video, catches all pointer events)
            Positioned.fill(
              child: PointerInterceptor(
                child: MouseRegion(
                  onHover: (_) => _onHover(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_showControls) {
                        setState(() => _showControls = false);
                      } else {
                        _onHover();
                      }
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Stack(
                        children: [
                          // Top Bar
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            top: _showControls ? 0 : -100,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: SafeArea(
                                bottom: false,
                                child: Row(
                                  children: [
                                    _buildSimpleIconButton(
                                      icon: Icons.arrow_back_rounded,
                                      onTap: () => Navigator.pop(context),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.channels != null
                                                ? widget
                                                    .channels![_currentIndex]
                                                    .name
                                                : widget.title,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Live TV',
                                            style: GoogleFonts.inter(
                                              color: AppColors.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildSimpleIconButton(
                                      icon: _isMuted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      onTap: _toggleMute,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Bottom Controls - styled like EPG
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            bottom: _showControls ? 16 : -100,
                            left: 24,
                            right: 24,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Previous Channel
                                    if (widget.channels != null &&
                                        widget.channels!.length > 1)
                                      _buildSimpleIconButton(
                                        icon: Icons.skip_previous_rounded,
                                        onTap: _previousChannel,
                                        size: 48,
                                      ),

                                    if (widget.channels != null &&
                                        widget.channels!.length > 1)
                                      const SizedBox(width: 24),

                                    // Play/Pause (Large)
                                    _buildSimpleIconButton(
                                      icon: _isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      onTap: _togglePlayPause,
                                      size: 56,
                                      iconSize: 32,
                                      highlighted: true,
                                    ),

                                    if (widget.channels != null &&
                                        widget.channels!.length > 1)
                                      const SizedBox(width: 24),

                                    // Next Channel
                                    if (widget.channels != null &&
                                        widget.channels!.length > 1)
                                      _buildSimpleIconButton(
                                        icon: Icons.skip_next_rounded,
                                        onTap: _nextChannel,
                                        size: 48,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // EPG Overlay (outside the main PointerInterceptor)
            if (widget.streamType == StreamType.live)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? 100 : -140,
                left: 24,
                right: 24,
                child: PointerInterceptor(
                  child: EpgOverlay(
                    playlist: widget.playlist,
                    streamId: widget.channels != null
                        ? widget.channels![_currentIndex].streamId
                        : widget.streamId,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // STANDARD PLAYER MODE (VOD/Series)
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInitialized) HtmlElementView(viewType: _viewId),

          // User interaction area
          Positioned.fill(
            child: PointerInterceptor(
              child: MouseRegion(
                onHover: (_) => _onHover(),
                child: GestureDetector(
                  onTap: () {
                    if (_showControls) {
                      setState(() => _showControls = false);
                    } else {
                      _onHover();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),

          // Controls Overlay
          if (_showControls || _isLoading)
            Positioned.fill(
              child: PointerInterceptor(
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Stack(
                    children: [
                      // Top Bar
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: GlassContainer(
                          height: 72,
                          borderRadius: 24,
                          opacity: 0.1,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildGlassIconButton(
                                icon: Icons.arrow_back_rounded,
                                onTap: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Center Play/Pause
                      Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: AppColors.primary)
                            : TvFocusableCard(
                                onTap: _togglePlayPause,
                                borderRadius: 100,
                                scaleFactor: 1.2,
                                focusColor: AppColors.primary,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            AppColors.primary.withOpacity(0.5),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                      ),

                      // Bottom Controls
                      Positioned(
                        bottom: 40,
                        left: 40,
                        right: 40,
                        child: GlassContainer(
                          borderRadius: 24,
                          opacity: 0.2, // Slightly more opaque for controls
                          border: true,
                          borderColor: Colors.white.withOpacity(0.1),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(Duration(
                                        seconds: _currentPosition.toInt())),
                                    style: GoogleFonts.inter(
                                        color: Colors.white70),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        activeTrackColor: AppColors.primary,
                                        inactiveTrackColor:
                                            Colors.white.withOpacity(0.2),
                                        thumbColor: Colors.white,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 8),
                                        overlayColor:
                                            AppColors.primary.withOpacity(0.2),
                                      ),
                                      child: Slider(
                                        value: _currentPosition,
                                        min: 0,
                                        max: _totalDuration,
                                        onChanged: (val) => setState(
                                            () => _currentPosition = val),
                                        onChangeStart: (_) =>
                                            setState(() => _isSeeking = true),
                                        onChangeEnd: (val) {
                                          _sendMessage(
                                              {'type': 'seek', 'value': val});
                                          Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                            if (mounted)
                                              setState(
                                                  () => _isSeeking = false);
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    _formatDuration(Duration(
                                        seconds: _totalDuration.toInt())),
                                    style: GoogleFonts.inter(
                                        color: Colors.white70),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildGlassIconButton(
                                    icon: Icons.replay_10_rounded,
                                    onTap: () => _sendMessage({
                                      'type': 'seek',
                                      'value': (_currentPosition - 10)
                                          .clamp(0, _totalDuration)
                                    }),
                                    transparent: true,
                                  ),
                                  const SizedBox(width: 24),
                                  _buildGlassIconButton(
                                    icon: _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    onTap: _togglePlayPause,
                                    size: 56,
                                    iconSize: 32,
                                  ),
                                  const SizedBox(width: 24),
                                  _buildGlassIconButton(
                                    icon: Icons.forward_10_rounded,
                                    onTap: () => _sendMessage({
                                      'type': 'seek',
                                      'value': (_currentPosition + 10)
                                          .clamp(0, _totalDuration)
                                    }),
                                    transparent: true,
                                  ),
                                  const Spacer(),
                                  _buildGlassIconButton(
                                    icon: _isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    onTap: _toggleMute,
                                    transparent: true,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildGlassIconButton(
                                    icon: Icons.aspect_ratio_rounded,
                                    onTap: _toggleFullscreen,
                                    transparent: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool transparent = false,
    double size = 48,
    double iconSize = 24,
  }) {
    // Button with direct Material/InkWell - PointerInterceptor is on outer container
    return Material(
      color: transparent ? Colors.transparent : Colors.white.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          print('[PlayerScreen] Button tapped: $icon');
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: transparent
                ? null
                : Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }

  // Simple Icon Button for Live TV player (no BackdropFilter issues)
  Widget _buildSimpleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 48,
    double iconSize = 24,
    bool highlighted = false,
  }) {
    return Material(
      color: highlighted
          ? AppColors.primary.withOpacity(0.2)
          : Colors.white.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          print('[PlayerScreen] Simple button tapped: $icon');
          onTap();
        },
        customBorder: const CircleBorder(),
        splashColor: AppColors.primary.withOpacity(0.3),
        highlightColor: AppColors.primary.withOpacity(0.1),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted
                  ? AppColors.primary.withOpacity(0.5)
                  : Colors.white.withOpacity(0.2),
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            color: highlighted ? AppColors.primary : Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
