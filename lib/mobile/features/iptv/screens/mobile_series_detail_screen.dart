import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/watch_history_provider.dart';
import 'mobile_player_screen.dart';
import '../../../../core/theme/app_colors.dart';

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
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error', style: const TextStyle(color: AppColors.textSecondary)),
                      TextButton(onPressed: _loadSeriesInfo, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildMobileContent(),
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
          backgroundColor: AppColors.background,
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
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
                        AppColors.background.withOpacity(0.8),
                        AppColors.background,
                      ],
                      stops: const [0.5, 0.8, 1.0],
                    ),
                  ),
                ),
                // Info Overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _seriesInfo!.name,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
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
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Text(
                            '${_seriesInfo!.episodes.keys.length} Seasons',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
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
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
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
          padding: const EdgeInsets.only(bottom: 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final episode = currentEpisodes[index];
                return _buildEpisodeTile(episode);
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

    return InkWell(
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            // Play Button / Indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isWatched ? AppColors.primary : Colors.white10,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWatched ? Icons.check : Icons.play_arrow,
                color: isWatched ? Colors.white : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'E${episode.episodeNum} - ${episode.title}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (episode.durationSecs != null && episode.durationSecs! > 0)
                    Text(
                      _formatDuration(episode.durationSecs!),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
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
