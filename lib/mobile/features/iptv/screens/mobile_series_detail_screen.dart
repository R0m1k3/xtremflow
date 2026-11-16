import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/models/playlist_config.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/watch_history_provider.dart';
// Explicit import for StreamType
import 'mobile_player_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

class MobileSeriesDetailScreen extends ConsumerStatefulWidget {
  final Series series;
  final PlaylistConfig playlist;

  const MobileSeriesDetailScreen({
    super.key,
    required this.series,
    required this.playlist,
  });

  @override
  ConsumerState<MobileSeriesDetailScreen> createState() =>
      _MobileSeriesDetailScreenState();
}

class _MobileSeriesDetailScreenState
    extends ConsumerState<MobileSeriesDetailScreen> {
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 44,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erreur : $_error',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadSeriesInfo,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : _buildMobileContent(),
    );
  }

  Widget _buildMobileContent() {
    if (_seriesInfo == null) return const SizedBox.shrink();

    final currentEpisodes = _seriesInfo!.episodes[_selectedSeason] ?? [];
    final seasonCount = _seriesInfo!.episodes.keys.length;
    final rating = _formatRating(_seriesInfo!.rating);
    final meta = [
      if (rating != null) '$rating / 10',
      '$seasonCount ${seasonCount > 1 ? 'saisons' : 'saison'}',
    ].join(' · ');

    return CustomScrollView(
      slivers: [
        // App Bar with Cover
        SliverAppBar(
          expandedHeight: 360,
          pinned: true,
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              tooltip: 'Retour',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.background.withValues(alpha: 0.6),
              ),
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
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
                    memCacheWidth: 800,
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: AppColors.surface),
                  ),
                // Scrim: the artwork fades into the page
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00101216),
                        Color(0xCC101216),
                        AppColors.background,
                      ],
                      stops: [0.45, 0.8, 1.0],
                    ),
                  ),
                ),
                // Info Overlay
                Positioned(
                  bottom: 16,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _seriesInfo!.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.display(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        style: AppTheme.body(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                _seriesInfo!.plot!,
                style: AppTheme.body(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

        // Seasons Filter
        SliverToBoxAdapter(
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _seriesInfo!.episodes.keys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final seasonNum = _seriesInfo!.episodes.keys.elementAt(index);
                final isSelected = seasonNum == _selectedSeason;
                return ChoiceChip(
                  label: Text('Saison $seasonNum'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedSeason = seasonNum);
                  },
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.accentFill,
                  labelStyle: AppTheme.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  showCheckmark: false,
                  side: BorderSide.none,
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // Episodes List
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 32),
          sliver: SliverList.separated(
            itemCount: currentEpisodes.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (context, index) =>
                _buildEpisodeTile(currentEpisodes[index]),
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
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            // Play Button / Indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isWatched ? AppColors.surfaceHigh : AppColors.accentFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWatched ? Icons.check : Icons.play_arrow_rounded,
                color: isWatched ? AppColors.textSecondary : AppColors.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${episode.episodeNum}. ${episode.title}',
                    style: AppTheme.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isWatched
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (episode.durationSecs != null && episode.durationSecs! > 0)
                    Text(
                      _formatDuration(episode.durationSecs!),
                      style: AppTheme.body(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontFeatures: AppTheme.tabular,
                      ),
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
    if (hours > 0) return '$hours h ${minutes.toString().padLeft(2, '0')}';
    return '$minutes min';
  }
}
