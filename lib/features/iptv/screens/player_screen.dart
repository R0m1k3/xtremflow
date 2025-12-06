import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../providers/xtream_provider.dart';
import '../widgets/epg_overlay.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';

/// Stream type enum for player
enum StreamType { live, vod, series }

/// Video player screen with EPG overlay for live streams
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
    this.containerExtension = 'm3u8',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final xtreamService = ref.read(xtreamServiceProvider(widget.playlist));
      
      // Generate stream URL based on type
      late String streamUrl;
      switch (widget.streamType) {
        case StreamType.live:
          streamUrl = xtreamService.getLiveStreamUrl(widget.streamId);
          break;
        case StreamType.vod:
          streamUrl = xtreamService.getVodStreamUrl(
            widget.streamId,
            widget.containerExtension,
          );
          break;
        case StreamType.series:
          streamUrl = xtreamService.getSeriesStreamUrl(
            widget.streamId,
            widget.containerExtension,
          );
          break;
      }

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
      );

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: $errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _errorMessage != null
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
                      Text(
                        'Failed to load stream',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    Center(
                      child: _chewieController != null
                          ? Chewie(controller: _chewieController!)
                          : const SizedBox.shrink(),
                    ),
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
