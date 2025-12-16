import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/lite_player_view.dart';

// ... (existing imports)
// ... (existing imports)
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_colors.dart';
import '../models/xtream_models.dart';
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

  Future<void> _initializePlayer(
      {double? startTimeOverride, bool isChannelSwitch = false}) async {
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
            currentStreamId, widget.containerExtension);
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
        setState(() => _isPlaying = data['status'] == 'playing');
      } else if (type == 'user_activity') {
        _onHover();
      }
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_isInitialized) {
      final iframe =
          html.document.getElementById(_viewId) as html.IFrameElement?;
      iframe?.contentWindow?.postMessage(message, '*');
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
    if (_isPlaying) {
      _sendMessage({'type': 'pause'});
    } else {
      _sendMessage({'type': 'play'});
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
    // Use stream type to determine player UI:
    // - Live TV: Lite player UI (minimal overlay)
    // - VOD/Series: Standard player UI (full controls)
    final isLiveTV = widget.streamType == StreamType.live;

    // LITE PLAYER MODE for Live TV: Simple iframe with native HTML5 controls, minimal Flutter overlay
    if (isLiveTV) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _onHover(),
          child: GestureDetector(
            onTap: () {
              if (_showControls) {
                setState(() => _showControls = false);
              } else {
                _onHover();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video Player (iframe with native controls)
                if (_isInitialized) HtmlElementView(viewType: _viewId),

                // Top Bar: Back Button + Title (with auto-hide)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  top: _showControls ? 24 : -80,
                  left: 24,
                  right: 24,
                  child: PointerInterceptor(
                    child: Row(
                      children: [
                        Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.arrow_back_rounded,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            widget.channels != null
                                ? widget.channels![_currentIndex].name
                                : widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black)
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Mute button for Live TV
                        Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _toggleMute,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                _isMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Channel Zapping Controls (with auto-hide)
                if (widget.channels != null && widget.channels!.length > 1)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    bottom: 160,
                    right: _showControls ? 24 : -80,
                    child: PointerInterceptor(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Previous Channel
                          Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _previousChannel,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(14),
                                child: Icon(Icons.keyboard_arrow_up,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Next Channel
                          Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _nextChannel,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(14),
                                child: Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // EPG Overlay (for Live TV, with auto-hide, higher position)
                if (widget.streamType == StreamType.live)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    bottom: _showControls ? 60 : -120,
                    left: 0,
                    right: 0,
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
          ),
        ),
      );
    }

    // STANDARD PLAYER MODE (Custom Flutter Overlay)
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Player Layer
          if (_isInitialized) HtmlElementView(viewType: _viewId),

          // 2. Interaction Layer
          Positioned.fill(
            child: PointerInterceptor(
              child: MouseRegion(
                onHover: (_) => _onHover(),
                child: GestureDetector(
                  onTap: () {
                    if (_showControls) {
                      setState(() => _showControls = false);
                    } else {
                      _onHover(); // Shows controls and starts timer
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),

          // 3. UI Overlay (Glassmorphism)
          if (_showControls || _isLoading)
            Positioned.fill(
              child: PointerInterceptor(
                child: Container(
                  color: Colors.black.withOpacity(0.3), // Dim background
                  child: Stack(
                    children: [
                      // Top Bar (Back + Title)
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: Row(
                          children: [
                            TvFocusableCard(
                              onTap: () => Navigator.pop(context),
                              borderRadius: 50,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.channels != null
                                      ? widget.channels![_currentIndex].name
                                      : widget.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                if (widget.streamType == StreamType.live &&
                                    widget.channels != null)
                                  Text(
                                    'Live TV',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: AppColors.live,
                                        fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Center Play/Pause (Animated)
                      Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : TvFocusableCard(
                                onTap: _togglePlayPause,
                                borderRadius: 100,
                                scaleFactor: 1.2,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                ),
                              ),
                      ),

                      // EPG Overlay
                      if (widget.streamType == StreamType.live)
                        Positioned(
                          bottom: 140,
                          left: 40,
                          child: EpgOverlay(
                            streamId: widget.channels != null
                                ? widget.channels![_currentIndex].streamId
                                : widget.streamId,
                            playlist: widget.playlist,
                          ),
                        ),

                      // Bottom Control Bar
                      Positioned(
                        bottom: 40,
                        left: 40,
                        right: 40,
                        child: GlassContainer(
                          borderRadius: 24,
                          opacity: 0.8,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress Bar (if not live)
                              if (widget.streamType != StreamType.live)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    children: [
                                      Text(
                                          _formatDuration(Duration(
                                              seconds:
                                                  _currentPosition.toInt())),
                                          style: const TextStyle(
                                              color: Colors.white70)),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: SliderTheme(
                                          data: const SliderThemeData(
                                            trackHeight: 4,
                                            thumbShape: RoundSliderThumbShape(
                                                enabledThumbRadius: 8),
                                            overlayShape:
                                                RoundSliderOverlayShape(
                                                    overlayRadius: 16),
                                            activeTrackColor: AppColors.primary,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: Colors.white,
                                          ),
                                          child: Slider(
                                            value: _currentPosition,
                                            min: 0,
                                            max: _totalDuration,
                                            onChangeStart: (value) {
                                              setState(() => _isSeeking = true);
                                            },
                                            onChanged: (value) {
                                              // Update UI immediately (optimistic update)
                                              setState(() =>
                                                  _currentPosition = value);
                                            },
                                            onChangeEnd: (value) {
                                              _sendMessage({
                                                'type': 'seek',
                                                'value': value
                                              });
                                              // Small delay to prevent jitter from incoming messages
                                              Future.delayed(
                                                  const Duration(
                                                      milliseconds: 500), () {
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
                                          style: const TextStyle(
                                              color: Colors.white70)),
                                    ],
                                  ),
                                ),

                              // Controls Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Channel Zapping for Live TV
                                  if (widget.streamType == StreamType.live &&
                                      widget.channels != null) ...[
                                    _buildTvControl(
                                        Icons.navigate_before_rounded,
                                        _previousChannel),
                                    const SizedBox(width: 32),
                                    _buildTvControl(Icons.navigate_next_rounded,
                                        _nextChannel),
                                  ],

                                  // Controls for VOD (Keep Skip buttons, they act as Prev/Next track if playlist or maybe seek)
                                  // The user said: "only for live tv, other buttons skip/prev must allow changing channel"
                                  // This implies for VOD they might want seek? But existing buttons were skip_previous/skip_next.
                                  // We keep them for VOD if channels list is present, or just hide them if not needed.
                                  // For now, I will restore them for VOD as well if channels > 0 (playlist mode)
                                  if (widget.streamType != StreamType.live &&
                                      widget.channels != null &&
                                      widget.channels!.isNotEmpty) ...[
                                    _buildTvControl(Icons.skip_previous_rounded,
                                        _previousChannel),
                                    const SizedBox(width: 32),
                                    _buildTvControl(
                                        Icons.skip_next_rounded, _nextChannel),
                                  ],

                                  const Spacer(),
                                  // Volume/Mute button
                                  _buildTvControl(
                                    _isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    _toggleMute,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildTvControl(
                                      Icons.subtitles_rounded, () {}),
                                  const SizedBox(width: 16),
                                  _buildTvControl(Icons.aspect_ratio_rounded,
                                      _toggleFullscreen),
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

  Widget _buildTvControl(IconData icon, VoidCallback onTap) {
    return TvFocusableCard(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
