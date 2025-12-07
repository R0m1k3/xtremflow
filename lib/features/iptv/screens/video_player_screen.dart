import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

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

  // Premium Features State
  BoxFit _fit = BoxFit.contain;
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _currentAudioTrack;

  @override
  void initState() {
    super.initState();
    
    // Initialize media_kit player
    _player = Player();
    _controller = VideoController(_player);
    
    // Load stream
    _player.open(Media(widget.streamUrl));
    _player.play();

    // Listen to tracks
    _player.stream.tracks.listen((tracks) {
      setState(() {
        _audioTracks = tracks.audio;
        _currentAudioTrack = _player.state.track.audio;
      });
    });
  }

  void _cycleAspectRatio() {
    setState(() {
      if (_fit == BoxFit.contain) {
        _fit = BoxFit.cover;
      } else if (_fit == BoxFit.cover) {
        _fit = BoxFit.fill;
      } else {
        _fit = BoxFit.contain;
      }
    });
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Format d\'image', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
               spacing: 8,
               children: [
                 _buildRatioChip('Original', BoxFit.contain),
                 _buildRatioChip('Remplir', BoxFit.cover),
                 _buildRatioChip('Étirer', BoxFit.fill),
               ],
            ),
            if (_audioTracks.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Pistes Audio', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _audioTracks.length,
                  itemBuilder: (context, index) {
                    final track = _audioTracks[index];
                    final isSelected = track == _currentAudioTrack;
                    return ListTile(
                      title: Text(track.language ?? track.label ?? 'Piste ${index + 1}', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(track.id, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
                      onTap: () {
                        _player.setAudioTrack(track);
                        setState(() => _currentAudioTrack = track);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRatioChip(String label, BoxFit fit) {
    final isSelected = _fit == fit;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
         setState(() => _fit = fit);
         Navigator.pop(context);
      },
      backgroundColor: Colors.white10,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(
                widget.title,
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.transparent, // Glass effect handled by body
              elevation: 0,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _showSettingsDialog,
                ),
                const SizedBox(width: 8),
              ],
            ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video display
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: _fit,
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
                        Colors.black87,
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
                      // SAFE AREA SPACER FOR APPBAR
                      if (!_isFullscreen)
                         const SizedBox(height: 80)
                      else 
                         const SizedBox.shrink(),

                      // Bottom controls
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
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
                                              AppColors.primary,
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
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  _formatDuration(duration),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
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
                              const SizedBox(height: 32),

                              // Playback controls
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Rewind
                                  IconButton(
                                    icon: const Icon(Icons.replay_10, size: 36),
                                    color: Colors.white,
                                    onPressed: () {
                                      final currentPos = _player.state.position;
                                      _player.seek(currentPos - const Duration(seconds: 10));
                                    },
                                  ),
                                  const SizedBox(width: 32),

                                  // Play/Pause
                                  StreamBuilder<bool>(
                                    stream: _player.stream.playing,
                                    builder: (context, snapshot) {
                                      final isPlaying = snapshot.data ?? false;
                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            isPlaying ? Icons.pause : Icons.play_arrow,
                                            size: 48,
                                          ),
                                          color: Colors.white,
                                          onPressed: () {
                                            _player.playOrPause();
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 32),

                                  // Forward
                                  IconButton(
                                    icon: const Icon(Icons.forward_10, size: 36),
                                    color: Colors.white,
                                    onPressed: () {
                                      final currentPos = _player.state.position;
                                      _player.seek(currentPos + const Duration(seconds: 10));
                                    },
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Footer Utils
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white70,
                                    ),
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
                    color: AppColors.primary,
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
