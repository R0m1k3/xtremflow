import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';

class LitePlayerView extends ConsumerStatefulWidget {
  final String streamUrl;
  final bool isLive;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  const LitePlayerView({
    super.key,
    required this.streamUrl,
    required this.isLive,
    this.onNext,
    this.onPrevious,
  });

  @override
  ConsumerState<LitePlayerView> createState() => _LitePlayerViewState();
}

class _LitePlayerViewState extends ConsumerState<LitePlayerView> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(LitePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _disposeControllers();
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() => _error = false);
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
      await _videoController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: false,
        isLive: widget.isLive,
        aspectRatio: _videoController.value.aspectRatio > 0
            ? _videoController.value.aspectRatio
            : 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),

        // Fullscreen configuration for Web/Mobile
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        useRootNavigator: true, // Crucial for escaping layout constraints

        // Orientation settings are often ignored or cause issues on web
        // but we keep them for native mobile if needed.
        // On web, the browser handles this.
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
        ],

        // Custom Controls to include Zapping
        additionalOptions: (context) {
          return <OptionItem>[
            if (widget.onNext != null)
              OptionItem(
                onTap: (context) {
                  widget.onNext!();
                  Navigator.of(context).pop(); // Close options menu
                },
                iconData: Icons.skip_next,
                title: 'Next Channel',
              ),
            if (widget.onPrevious != null)
              OptionItem(
                onTap: (context) {
                  widget.onPrevious!();
                  Navigator.of(context).pop(); // Close options menu
                },
                iconData: Icons.skip_previous,
                title: 'Previous Channel',
              ),
          ];
        },
      );

      _chewieController!.addListener(() {
        if (mounted) setState(() {});
      });

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing Lite Player: $e');
      setState(() => _error = true);
    }
  }

  void _disposeControllers() {
    _videoController.dispose();
    _chewieController?.dispose();
    _chewieController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text('Error loading video',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _disposeControllers();
                _initializePlayer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      return Stack(
        children: [
          Chewie(controller: _chewieController!),

          // Right-Side Overlays (Zapping + Fullscreen)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fullscreen Toggle
                  IconButton(
                    onPressed: () {
                      // For Web, ensure we use the built-in fullscreen transition
                      // which is more compatible with Safari/Chrome security
                      if (_chewieController?.isFullScreen == true) {
                        _chewieController?.exitFullScreen();
                      } else {
                        // On web, sometimes we need to toggle more than once
                        // to ensure the browser captures the intent
                        _chewieController?.enterFullScreen();
                      }
                    },
                    icon: Icon(
                        _chewieController?.isFullScreen == true
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                        size: 32),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black87,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Zapping Controls
                  if (widget.onPrevious != null || widget.onNext != null)
                    GlassContainer(
                      borderRadius: 16,
                      opacity: 0.3,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onPrevious != null)
                            IconButton(
                              onPressed: widget.onPrevious,
                              icon: const Icon(Icons.keyboard_arrow_up,
                                  color: Colors.white, size: 36),
                              tooltip: 'Previous Channel',
                            ),
                          const SizedBox(height: 8),
                          if (widget.onNext != null)
                            IconButton(
                              onPressed: widget.onNext,
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white, size: 36),
                              tooltip: 'Next Channel',
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return const Center(
        child: CircularProgressIndicator(color: AppColors.primary));
  }
}
