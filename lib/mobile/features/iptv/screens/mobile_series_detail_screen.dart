import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/watch_history_provider.dart';
import '../../../../features/iptv/screens/player_screen.dart'; // Explicit import for StreamType
import 'mobile_player_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';

class MobileSeriesDetailScreen extends ConsumerStatefulWidget {
  final Series series;
  final PlaylistConfig playlist;

  const MobileSeriesDetailScreen({
    super.key,
    required this.series,
    required this.playlist,
  });

  @override
  ConsumerState<MobileSeriesDetailScreen> createState() => _MobileSeriesDetailScreenState();
}

class _MobileSeriesDetailScreenState extends ConsumerState<MobileSeriesDetailScreen> {
  SeriesInfo? _seriesInfo;
  bool _isLoading = true;
  String? _error;
  int _selectedSeason = 1;

  @override
  void initState() {
    super.initState();
    _loadSeriesInfo();
  }

  String? _formatRating(String? rating) {
    if (rating == null || rating.isEmpty) return null;
    final value = double.tryParse(rating);
    if (value != null) {
      return value.toStringAsFixed(1);
    }
    return rating;
  }

  Future<void> _loadSeriesInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final info = await service.getSeriesInfo(widget.series.seriesId);

      if (mounted) {
        setState(() {
          _seriesInfo = info;
          _isLoading = false;
          if (info.episodes.isNotEmpty) {
            _selectedSeason = info.episodes.keys.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Global Background
           Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [Color(0xFF1C1C1E), Color(0xFF000000)],
              ),
            ),
          ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_error != null)
             Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text('Error: $_error', style: GoogleFonts.inter(color: Colors.white70)),
                  TextButton(onPressed: _loadSeriesInfo, child: const Text('Retry')),
                ],
              ),
            )
          else
            _buildMobileContent(),
        ],
      ),
    );
  }

  Widget _buildMobileContent() {
    if (_seriesInfo == null) return const SizedBox.shrink();

    final currentEpisodes = _seriesInfo!.episodes[_selectedSeason] ?? [];

    return CustomScrollView(
      slivers: [
        // App Bar with Cover
        SliverAppBar(
          expandedHeight: 400,
          pinned: true,
          backgroundColor: Colors.transparent, // Let background show through
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (_seriesInfo!.cover != null)
                  CachedNetworkImage(
                    imageUrl: _seriesInfo!.cover!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: Colors.grey.shade900),
                  ),
                // Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                        Colors.black, // Merge into body background
                      ],
                      stops: const [0.5, 0.8, 1.0],
                    ),
                  ),
                ),
                // Info Overlay
                Positioned(
                  bottom: 16, left: 16, right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _seriesInfo!.name,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_seriesInfo!.rating != null) ...[
                            const Icon(Icons.star, size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              _formatRating(_seriesInfo!.rating!)!,
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Text(
                            '${_seriesInfo!.episodes.keys.length} Seasons',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Plot
        if (_seriesInfo!.plot != null && _seriesInfo!.plot!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _seriesInfo!.plot!,
                style: GoogleFonts.inter(color: Colors.white70, height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

        // Seasons Filter
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _seriesInfo!.episodes.keys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final seasonNum = _seriesInfo!.episodes.keys.elementAt(index);
                final isSelected = seasonNum == _selectedSeason;
                return ChoiceChip(
                  label: Text('Season $seasonNum'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedSeason = seasonNum);
                  },
                  backgroundColor: Colors.white.withOpacity(0.1),
                  selectedColor: AppColors.primary,
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  showCheckmark: false,
                  side: BorderSide.none,
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Episodes List
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final episode = currentEpisodes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildEpisodeTile(episode),
                );
              },
              childCount: currentEpisodes.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeTile(Episode episode) {
    final watchHistory = ref.watch(watchHistoryProvider);
    final episodeKey = WatchHistory.episodeKey(
      widget.series.seriesId,
      _selectedSeason,
      episode.episodeNum,
    );
    final isWatched = watchHistory.isEpisodeWatched(episodeKey);

    return GlassContainer(
      borderRadius: 12,
      opacity: 0.1,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          ref.read(watchHistoryProvider.notifier).markEpisodeWatched(episodeKey);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MobilePlayerScreen(
                streamId: episode.id,
                title: '${widget.series.name} - ${episode.title}',
                playlist: widget.playlist,
                streamType: StreamType.series,
                containerExtension: episode.containerExtension ?? 'mkv',
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // Play Button / Indicator
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isWatched ? AppColors.primary : Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWatched ? Icons.check : Icons.play_arrow_rounded,
                  color: isWatched ? Colors.white : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'E${episode.episodeNum} - ${episode.title}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episode.durationSecs != null && episode.durationSecs! > 0)
                      Text(
                        _formatDuration(episode.durationSecs!),
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
