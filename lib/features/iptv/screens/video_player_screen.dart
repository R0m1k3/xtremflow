import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:google_fonts/google_fonts.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String? posterUrl;

  const VideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.posterUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isFullscreen = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    
    // Initialize media_kit player
    _player = Player();
    _controller = VideoController(_player);
    
    // Load stream
    _player.open(Media(widget.streamUrl));
    _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(
                widget.title,
                style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video display
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
              ),
            ),

            // Custom controls overlay
            if (_showControls)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black87,
                      ],
                      stops: const [0.0, 0.2, 0.7, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top bar with title
                      if (!_isFullscreen)
                        const SizedBox.shrink()
                      else
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: GoogleFonts.roboto(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Bottom controls
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress bar
                              StreamBuilder<Duration>(
                                stream: _player.stream.position,
                                builder: (context, positionSnapshot) {
                                  return StreamBuilder<Duration>(
                                    stream: _player.stream.duration,
                                    builder: (context, durationSnapshot) {
                                      final position = positionSnapshot.data ?? Duration.zero;
                                      final duration = durationSnapshot.data ?? Duration.zero;
                                      final progress = duration.inMilliseconds > 0
                                          ? position.inMilliseconds / duration.inMilliseconds
                                          : 0.0;

                                      return Column(
                                        children: [
                                          LinearProgressIndicator(
                                            value: progress.clamp(0.0, 1.0),
                                            backgroundColor: Colors.white24,
                                            valueColor: const AlwaysStoppedAnimation<Color>(
                                              Colors.red,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (duration.inSeconds > 0)
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  _formatDuration(position),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  _formatDuration(duration),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 16),

                              // Playback controls
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Rewind
                                  IconButton(
                                    icon: const Icon(Icons.replay_10, size: 32),
                                    color: Colors.white,
                                    onPressed: () {
                                      final currentPos = _player.state.position;
                                      _player.seek(currentPos - const Duration(seconds: 10));
                                    },
                                  ),
                                  const SizedBox(width: 24),

                                  // Play/Pause
                                  StreamBuilder<bool>(
                                    stream: _player.stream.playing,
                                    builder: (context, snapshot) {
                                      final isPlaying = snapshot.data ?? false;
                                      return IconButton(
                                        icon: Icon(
                                          isPlaying ? Icons.pause : Icons.play_arrow,
                                          size: 48,
                                        ),
                                        color: Colors.white,
                                        onPressed: () {
                                          _player.playOrPause();
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 24),

                                  // Forward
                                  IconButton(
                                    icon: const Icon(Icons.forward_10, size: 32),
                                    color: Colors.white,
                                    onPressed: () {
                                      final currentPos = _player.state.position;
                                      _player.seek(currentPos + const Duration(seconds: 10));
                                    },
                                  ),
                                  const Spacer(),

                                  // Fullscreen toggle
                                  IconButton(
                                    icon: Icon(
                                      _isFullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      size: 32,
                                    ),
                                    color: Colors.white,
                                    onPressed: _toggleFullscreen,
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

            // Loading indicator
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snapshot) {
                final isBuffering = snapshot.data ?? false;
                if (!isBuffering) return const SizedBox.shrink();
                
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.red,
                    strokeWidth: 3,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
