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
import '../widgets/clock_widget.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';

import '../../../core/widgets/themed_loading_screen.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:ui' as ui; // Essential for BackdropFilter
import '../../../core/theme/app_colors.dart';

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
  bool _isPlaying = true;
  double _currentPosition = 0;

  double _totalDuration = 1;
  double _volume = 1.0;
  double _previousVolume = 1.0;
  bool _isFullscreen = false;
  Timer? _controlsTimer;
  StreamSubscription? _messageSubscription;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
  
  // Premium Features State
  List<Map<String, dynamic>> _audioTracks = [];
  String _aspectRatio = 'contain';



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
            setState(() {
              _currentPosition = currentTime;
              _totalDuration = duration > 0 ? duration : 1;
            });
            ref.read(playbackPositionsProvider.notifier).savePosition(
              _contentId, currentTime, duration
            );
          } else if (type == 'playback_status') {
            final status = data['status'];
            setState(() {
              _isPlaying = status == 'playing';
            });
          } else if (type == 'playback_ended' && _contentId.isNotEmpty) {
          } else if (type == 'user_activity') {
            _onHover();
          } else if (type == 'audio_tracks') {
            final tracks = List<Map<String, dynamic>>.from(data['tracks']);
            setState(() {
              _audioTracks = tracks;
            });
          }
        }
      } catch (e) {
        debugPrint('Error handling postMessage: $e');
      }
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    // Helper to send message to iframe
    debugPrint('Sending message to iframe ($_viewId): $message');
    final iframe = html.document.getElementById(_viewId) as html.IFrameElement?;
    if (iframe == null) {
       debugPrint('ERROR: Iframe with ID $_viewId not found!');
    } else {
       iframe.contentWindow?.postMessage(message, '*');
    }
  }

  void _setAspectRatio(String mode) {
    setState(() {
      _aspectRatio = mode;
    });
    _sendMessage({'type': 'set_aspect_ratio', 'value': mode});
  }

  void _setAudioTrack(int index) {
    _sendMessage({'type': 'set_audio_track', 'index': index});
    Navigator.pop(context); // Close settings
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
    _controlsTimer = Timer(const Duration(seconds: 4), _hideControls);
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    _sendMessage({'type': _isPlaying ? 'play' : 'pause'});
    _onHover(); // Keep controls visible
  }

  void _seekTo(double value) {
    setState(() {
      _currentPosition = value;
    });
    
    // Check if we are using server-side transcoding for VOD/Series
    // If so, we must reload the player because we can't seek in a piped stream directly via JS
    final settings = ref.read(iptvSettingsProvider);
    final isTranscoding = widget.streamType != StreamType.live && settings.streamQuality != StreamQuality.high;
    
    if (isTranscoding) {
       debugPrint('Seeking in transcoded VOD - reloading player at ${value.round()}s');
       // Reload player with new start time
       // This will trigger _initializePlayer with the current position effectively
       // But _initializePlayer reads from _currentPosition? No, it reads from provider OR starts at 0.
       // We need to force it to start at 'value'.
       // Best way is to just call _initializePlayer which builds the URL.
       // But _initializePlayer checks logic.
       
       // Actually _initializePlayer uses: startTime = positions.getPosition(_contentId);
       // So if we save the position first, it might pick it up?
       // Let's pass the seek time explicitly to a reload method or updating state.
       
       // Simplest: Update the provider, then re-init.
       ref.read(playbackPositionsProvider.notifier).savePosition(_contentId, value, _totalDuration);
       _initializePlayer(startTimeOverride: value);
       
    } else {
       // Direct play or Live - standard seeking
       _sendMessage({'type': 'seek', 'value': value});
    }
    
    _onHover();
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      if (value > 0) {
        _previousVolume = value;
      }
    });
    _sendMessage({'type': 'set_volume', 'value': value});
    _onHover();
  }

  void _toggleMute() {
    if (_volume > 0) {
      // Mute
      setState(() {
        _previousVolume = _volume;
        _volume = 0;
      });
      _sendMessage({'type': 'set_volume', 'value': 0.0});
    } else {
      // Unmute (restore previous volume)
      setState(() {
        _volume = _previousVolume > 0 ? _previousVolume : 0.5;
      });
      _sendMessage({'type': 'set_volume', 'value': _volume});
    }
    _onHover();
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

  void _toggleFullscreen() {
    final document = html.document;
    final docElement = document.documentElement;
    
    if (_isFullscreen) {
      document.exitFullscreen();
      setState(() {
        _isFullscreen = false;
      });
    } else {
      docElement?.requestFullscreen();
      setState(() {
        _isFullscreen = true;
      });
    }
    _onHover();
  }

  Future<void> _initializePlayer({double? startTimeOverride}) async {
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
        // For VOD and Series
        
        // CHECK QUALITY SETTING
        // If Quality is NOT High, we force transcoding to ensure audio compatibility (AAC)
        // This solves "No Sound" issues with AC3/DTS on mobile/web.
        // NOTE: For MKV files with unsupported audio, user should select Low/Medium quality.
        final settings = ref.read(iptvSettingsProvider);
        final useTranscoding = settings.streamQuality != StreamQuality.high;
        
        if (useTranscoding) {
           setState(() {
            _statusMessage = 'Starting VOD Transcoding (Audio Fix)...';
           });
           
           final baseUrl = html.window.location.origin;
           final vodStreamUrl = widget.streamType == StreamType.vod 
               ? xtreamService.getVodStreamUrl(currentStreamId, widget.containerExtension)
               : xtreamService.getSeriesStreamUrl(currentStreamId, widget.containerExtension);
           
           final encodedUrl = Uri.encodeComponent(vodStreamUrl);
           final qualityParam = switch (settings.streamQuality) {
              StreamQuality.low => 'low',
              StreamQuality.medium => 'medium',
              StreamQuality.high => 'high',
           };
           
           // Calculate start time for seeking support
           // If override provided (seeking), use it. Else check provider resume.
           double startSeconds = startTimeOverride ?? 0;
           if (startTimeOverride == null && _contentId.isNotEmpty) {
              final positions = ref.read(playbackPositionsProvider);
              final saved = positions.getPosition(_contentId);
              if (saved > 0) startSeconds = saved;
           }
           
           // Construct URL with start param
           // Note: We force extension to .ts for mpegts.js compatibility
           final streamEndpoint = '$baseUrl/api/stream/$currentStreamId?url=$encodedUrl&quality=$qualityParam&start=${startSeconds.round()}&ext=.ts';
           
           debugPrint('PlayerScreen: Streaming Transcoded VOD: $streamEndpoint');
           hlsUrl = streamEndpoint;
           
        } else {
          // Direct Play (High Quality) - Original behavior
          final streamUrl = widget.streamType == StreamType.vod
              ? xtreamService.getVodStreamUrl(currentStreamId, widget.containerExtension)
              : xtreamService.getSeriesStreamUrl(currentStreamId, widget.containerExtension);
          hlsUrl = streamUrl;
          debugPrint('PlayerScreen: Direct playback URL (High Quality): $hlsUrl');
        }
      }
      
      setState(() {
        _statusMessage = 'Loading player...';
      });
      
      // Get resume position for VOD/Series
      double startTime = startTimeOverride ?? 0;
      if (startTime <= 0 && widget.streamType != StreamType.live && _contentId.isNotEmpty) {
        final positions = ref.read(playbackPositionsProvider);
        startTime = positions.getPosition(_contentId);
        if (startTime > 0) {
          debugPrint('PlayerScreen: Resuming from ${startTime.toStringAsFixed(0)}s');
        }
      }
      
      // If we are Transcoding VOD, the start time is handled by the server (burned into stream)
      // So we should NOT pass startTime to player.html, otherwise it might try to seek 
      // on a stream that already starts at X.
      // EXCEPTION: If player.html receives an MPEG-TS stream that has timestamps starting at X,
      // setting currentTime might be redundant or needed depending on player impl.
      // Safest: If Transcoding, don't pass startTime to player.html (server handles it).
      // If Direct Play, pass startTime.
      
      final settings = ref.read(iptvSettingsProvider);
      final isTranscoding = widget.streamType != StreamType.live && settings.streamQuality != StreamQuality.high;
      
      final encodedHlsUrl = Uri.encodeComponent(hlsUrl);
      final playerUrl = (!isTranscoding && startTime > 0)
          ? 'player.html?url=$encodedHlsUrl&startTime=${startTime.toStringAsFixed(0)}'
          : 'player.html?url=$encodedHlsUrl';
      
      debugPrint('PlayerScreen: Player URL: $playerUrl');
      
      // Generate a new view ID for every load to force iframe recreation
      _viewId = 'iptv-player-${widget.streamId}-${DateTime.now().millisecondsSinceEpoch}';

      // Register platform view factory
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..id = _viewId // CRITICAL: Set ID for getElementById lookup
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
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    
    // Load preferred aspect ratio from settings
    final settings = ref.read(iptvSettingsProvider);
    _aspectRatio = settings.preferredAspectRatio;
    
    _initializePlayer();
    _setupMessageListener();
  }

  void _showSettingsDialog() {
    // Read current settings
    final settingsNotifier = ref.read(iptvSettingsProvider.notifier);
    // We use a local state variable for the switch in the dialog, 
    // initialized from the provider.
    bool showClock = ref.read(iptvSettingsProvider).showClock;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => PointerInterceptor(
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Transform.scale(
                  scale: 0.9 + (0.1 * value),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                ),
                child: Container(
                  width: 400,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Réglages',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white54),
                                  onPressed: () => Navigator.pop(context),
                                  tooltip: 'Fermer',
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            const Text('FORMAT D\'IMAGE', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                   _buildRatioOption('Original', 'contain', Icons.crop_original, setDialogState),
                                   _buildRatioOption('Remplir', 'cover', Icons.crop_free, setDialogState),
                                   _buildRatioOption('Étirer', 'fill', Icons.aspect_ratio, setDialogState),
                                ],
                              ),
                            ),
                          if (_audioTracks.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            const Text('AUDIO', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 12),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: _audioTracks.map((track) {
                                      return Material(
                                        color: Colors.transparent,
                                        child: ListTile(
                                          title: Text(track['label'] ?? 'Piste ${track['id']}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                          subtitle: Text(track['lang'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                          onTap: () {
                                            _setAudioTrack(track['id']);
                                            setDialogState(() {});
                                          },
                                          dense: true,
                                          leading: const Icon(Icons.audiotrack, size: 18, color: Colors.white54),
                                          hoverColor: Colors.white.withOpacity(0.1),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                            const Text('AFFICHAGE', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: showClock,
                              onChanged: (val) {
                                setDialogState(() {
                                  showClock = val;
                                });
                                settingsNotifier.setShowClock(val);
                              },
                              title: const Text('Afficher l\'heure', style: TextStyle(color: Colors.white, fontSize: 14)),
                              secondary: const Icon(Icons.access_time, color: Colors.white54),
                              activeColor: AppColors.primary,
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRatioOption(String label, String value, IconData icon, StateSetter setDialogState) {
    final isSelected = _aspectRatio == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          debugPrint('Changing Aspect Ratio to: $value');
          _setAspectRatio(value);
          // Save preference
          ref.read(iptvSettingsProvider.notifier).setPreferredAspectRatio(value);
          setDialogState(() {}); // Force rebuild of the dialog content
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceVariant : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: Colors.white12) : null,
            boxShadow: isSelected ? [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.white54, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);
    return Scaffold(
      appBar: _showControls ? AppBar(
        title: Text(widget.channels != null && widget.channels!.isNotEmpty 
            ? widget.channels![_currentIndex].name 
            : widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PointerInterceptor(
            child: IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
              tooltip: 'Réglages',
            ),
          ),
          const SizedBox(width: 16),
        ],
      ) : null,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: ClipRect(
        child: MouseRegion(
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

                          // GLOBAL INTERACTION LAYER (Fixes Click/Hover issues)
                          // This transparent layer sits ABOVE the iframe but BELOW the controls.
                          // It intercepts all pointer events, enabling Flutter to handle them.
                          Positioned.fill(
                            child: PointerInterceptor(
                              child: MouseRegion(
                                onHover: (_) => _onHover(),
                                child: GestureDetector(
                                  // Toggle controls on tap
                                  onTap: () {
                                    if (_showControls) {
                                      _hideControls();
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
                          
                          // Hover Controls Layer
                          if (_showControls) ...[
                            // Volume Slider (Left Side)
                            Positioned(
                              left: 24,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Container(
                                  height: 200,
                                  width: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Column(
                                    children: [
                                      PointerInterceptor(
                                        child: IconButton(
                                          icon: Icon(
                                            _volume == 0 
                                                ? Icons.volume_off 
                                                : _volume < 0.5 ? Icons.volume_down : Icons.volume_up,
                                            color: Colors.white, 
                                            size: 20
                                          ),
                                          onPressed: _toggleMute,
                                          tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: RotatedBox(
                                          quarterTurns: 3,
                                          child: SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 4,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                              activeTrackColor: Colors.white,
                                              inactiveTrackColor: Colors.white24,
                                              thumbColor: AppColors.primary,
                                              overlayColor: AppColors.primary.withOpacity(0.2),
                                            ),
                                            child: Slider(
                                              value: _volume,
                                              onChanged: _setVolume,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Playback Controls (Centered Row: Previous - Play/Pause - Next - Fullscreen)
                            Positioned(
                              top: null,
                              bottom: 150,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: PointerInterceptor(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Previous Channel Button
                                      if (widget.channels != null && widget.channels!.isNotEmpty)
                                        InkWell(
                                          onTap: _playPrevious,
                                          borderRadius: BorderRadius.circular(50),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.skip_previous,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                        ),
                                      if (widget.channels != null && widget.channels!.isNotEmpty)
                                        const SizedBox(width: 24),
                                      
                                      // Play/Pause Button
                                      InkWell(
                                        onTap: _togglePlayPause,
                                        borderRadius: BorderRadius.circular(50),
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.5),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                          child: Icon(
                                            _isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                      
                                      // Next Channel Button
                                      if (widget.channels != null && widget.channels!.isNotEmpty)
                                        const SizedBox(width: 24),
                                      if (widget.channels != null && widget.channels!.isNotEmpty)
                                        InkWell(
                                          onTap: _playNext,
                                          borderRadius: BorderRadius.circular(50),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.skip_next,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                        ),
                                      
                                      // Fullscreen Button
                                      const SizedBox(width: 32),
                                      InkWell(
                                        onTap: _toggleFullscreen,
                                        borderRadius: BorderRadius.circular(50),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.5),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Progress Bar (Bottom) - Only for VOD/Series
                            if (widget.streamType != StreamType.live)
                              Positioned(
                                bottom: 80,
                                left: 24,
                                right: 24,
                                child: PointerInterceptor(
                                  child: Column(
                                    children: [
                                      SliderTheme(
                                        data: SliderThemeData(
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                          activeTrackColor: AppColors.primary,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: AppColors.primary,
                                          overlayColor: AppColors.primary.withOpacity(0.2),
                                        ),
                                        child: Slider(
                                          value: _currentPosition,
                                          max: _totalDuration,
                                          onChanged: (value) {
                                            _seekTo(value);
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDuration(Duration(seconds: _currentPosition.toInt())),
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                            ),
                                            Text(
                                              _formatDuration(Duration(seconds: _totalDuration.toInt())),
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              
                            // EPG Overlay
                            if (widget.streamType == StreamType.live)
                              Positioned(
                                bottom: 100, // Move up above progress bar area/OS safe area
                                left: 0,
                                right: 0,
                                child: PointerInterceptor(
                                    child: EpgOverlay(
                                      streamId: widget.channels != null 
                                          ? widget.channels![_currentIndex].streamId
                                          : widget.streamId,
                                      playlist: widget.playlist,
                                    ),
                                  ),
                              ),
                          ],
                          
                          // Clock Widget (Always visible if enabled, or only with controls? User asked "met l'heure dans les options")
                          // Positioned in top right
                          if (settings.showClock)
                             AnimatedPositioned(
                               duration: const Duration(milliseconds: 300),
                               curve: Curves.easeInOut,
                               top: 24, // Fixed top
                               right: _showControls ? 80 : 24, // Shift left when settings visible
                               child: const IgnorePointer(
                                child: ClockWidget(
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
        ),
      ),
    );
  }
}
