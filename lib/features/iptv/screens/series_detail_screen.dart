import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/widgets/themed_loading_screen.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/playback_positions_provider.dart';
import '../providers/watch_history_provider.dart';
import '../widgets/live_widgets.dart' show SectionTitle;
import 'player_screen.dart';

/// Series detail: artwork and synopsis on top, the seasons, then the
/// episodes of the season picked.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  final Series series;
  final PlaylistConfig playlist;

  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.playlist,
  });

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  SeriesInfo? _seriesInfo;
  bool _isLoading = true;
  String? _error;
  int _selectedSeason = 1;

  @override
  void initState() {
    super.initState();
    _loadSeriesInfo();
  }

  Future<void> _loadSeriesInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final info = await service.getSeriesInfo(widget.series.seriesId);

      setState(() {
        _seriesInfo = info;
        _isLoading = false;
        // Select first available season
        if (info.episodes.isNotEmpty) {
          _selectedSeason = info.episodes.keys.first;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? _formatRating(String? rating) {
    if (rating == null || rating.isEmpty) return null;
    final value = double.tryParse(rating);
    if (value != null) {
      return value.toStringAsFixed(1);
    }
    return rating;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AmbientBackground(
        child: _isLoading
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  const Expanded(child: ThemedLoading()),
                ],
              )
            : _error != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  Expanded(child: _buildError()),
                ],
              )
            : _buildContent(),
      ),
    );
  }

  /// Back button and the series name (loading and error states).
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Row(
        children: [
          _BackButton(onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.series.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Impossible de charger la série',
              style: AppTheme.body(fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadSeriesInfo,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_seriesInfo == null) return const SizedBox.shrink();
    final info = _seriesInfo!;

    final currentEpisodes = info.episodes[_selectedSeason] ?? [];
    final count = currentEpisodes.length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(info)),

        // Season selector
        if (info.episodes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('Saisons'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: info.episodes.keys.map((seasonNum) {
                      final isSelected = seasonNum == _selectedSeason;
                      return ChoiceChip(
                        label: Text('Saison $seasonNum'),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedSeason = seasonNum);
                          }
                        },
                        showCheckmark: false,
                        color: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColors.accentFill
                              : AppColors.surface,
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : AppColors.hairline,
                        ),
                        shape: const StadiumBorder(),
                        labelStyle: AppTheme.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

        // Episodes of the season
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Saison $_selectedSeason · $count épisode${count > 1 ? 's' : ''}',
              style: AppTheme.body(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                fontFeatures: AppTheme.tabular,
              ),
            ),
          ),
        ),
        if (currentEpisodes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 32),
              child: Text(
                'Aucun épisode',
                style: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList.builder(
              itemCount: currentEpisodes.length,
              itemBuilder: (context, index) {
                final episode = currentEpisodes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildEpisodeTile(episode),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Artwork on the right under a veil, back button, title, rating, plot.
  Widget _buildHero(SeriesInfo info) {
    final rating = info.rating != null ? _formatRating(info.rating!) : null;
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (info.cover != null)
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: .62,
                heightFactor: 1,
                child: CachedNetworkImage(
                  imageUrl: info.cover!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: 1280,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Veil from the left, then down into the page.
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.heroScrim),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00101216), AppColors.background],
                ),
              ),
            ),
          ),
          Positioned(
            top: 28,
            left: 32,
            child: _BackButton(onPressed: () => Navigator.pop(context)),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 24,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.display(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating,
                            style: AppTheme.body(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (info.plot != null && info.plot!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        info.plot!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 15,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playEpisode(Episode episode, String episodeKey) async {
    // Mark as watched when playing
    ref.read(watchHistoryProvider.notifier).markEpisodeWatched(episodeKey);

    // Fetch actual duration from API if not available
    Duration? episodeDuration;
    if (episode.durationSecs != null && episode.durationSecs! > 0) {
      episodeDuration = Duration(seconds: episode.durationSecs!);
    } else {
      // Try to fetch from API using getVodDuration (episodes are often queryable as VODs)
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final durationSecs = await service.getVodDuration(episode.id);
      if (durationSecs != null && durationSecs > 0) {
        episodeDuration = Duration(seconds: durationSecs);
      }
    }

    if (!mounted) return;

    // Reprise de lecture : le player sauvegarde la position sous
    // episode.id, on la relit ici pour reprendre où on s'était arrêté.
    final positions = ref.read(playbackPositionsProvider);
    final resumeAt = positions.hasPosition(episode.id)
        ? positions.getPosition(episode.id)
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamId: episode.id,
          title: '${widget.series.name} - ${episode.title}',
          playlist: widget.playlist,
          streamType: StreamType.series,
          containerExtension: episode.containerExtension ?? 'mkv',
          duration: episodeDuration,
          startTime: resumeAt,
        ),
      ),
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

    return TVFocusable(
      key: ValueKey(episode.id),
      paintsOwnFocus: true,
      scale: 1.0,
      borderRadius: BorderRadius.circular(10),
      onPressed: () => _playEpisode(episode, episodeKey),
      // Toggle watched on long press
      onLongPress: () => ref
          .read(watchHistoryProvider.notifier)
          .toggleEpisodeWatched(episodeKey),
      longPressDuration: const Duration(milliseconds: 700),
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final secondary = lit
              ? AppColors.onFocusMuted
              : AppColors.textSecondary;
          final mark = lit ? AppColors.accentOnLight : AppColors.accent;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: GlassDecoration(
              lit: lit ? 1 : 0,
              radius: 10,
              bare: true,
              halo: false,
            ),
            child: Row(
              children: [
                // Episode number, or a check once watched
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lit ? AppColors.focusTrack : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isWatched
                      ? Icon(Icons.check_rounded, color: mark, size: 20)
                      : Text(
                          '${episode.episodeNum}',
                          style: AppTheme.body(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: lit
                                ? AppColors.onFocus
                                : AppColors.textPrimary,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                ),
                const SizedBox(width: 14),

                // Episode info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        style: AppTheme.body(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: lit
                              ? AppColors.onFocus
                              : isWatched
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (episode.durationSecs != null &&
                          episode.durationSecs! > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatDuration(episode.durationSecs!),
                          style: AppTheme.body(
                            fontSize: 14,
                            color: secondary,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Play icon
                Icon(
                  isWatched ? Icons.replay_rounded : Icons.play_arrow_rounded,
                  color: secondary,
                  size: 24,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h ${minutes.toString().padLeft(2, '0')}';
    }
    return '$minutes min';
  }
}

/// Back to the previous page.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Retour',
      child: TVFocusable(
        paintsOwnFocus: true,
        scale: 1.0,
        borderRadius: BorderRadius.circular(12),
        onPressed: onPressed,
        child: Builder(
          builder: (context) {
            final lit = TVFocusable.isFocused(context);
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: lit ? AppColors.focusTop : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                color: lit ? AppColors.onFocus : AppColors.textPrimary,
              ),
            );
          },
        ),
      ),
    );
  }
}
