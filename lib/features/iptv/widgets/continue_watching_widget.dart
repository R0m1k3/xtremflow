import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/recommendations_provider.dart';
import '../../../core/models/playlist_config.dart';
import '../models/playlist.dart';

/// Widget showing "Continue Watching" section
class ContinueWatchingWidget extends ConsumerStatefulWidget {
  final Playlist playlist;
  final List<Playlist> content;
  final VoidCallback? onItemTap;

  const ContinueWatchingWidget({
    Key? key,
    required this.playlist,
    required this.content,
    this.onItemTap,
  }) : super(key: key);

  @override
  ConsumerState<ContinueWatchingWidget> createState() =>
      _ContinueWatchingWidgetState();
}

class _ContinueWatchingWidgetState
    extends ConsumerState<ContinueWatchingWidget> {
  @override
  Widget build(BuildContext context) {
    final watchHistory = ref.watch(watchHistoryProvider);
    final continueWatching =
        RecommendationService.getContinueWatching(watchHistory, widget.content);

    if (continueWatching.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Continue Watching',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to full continue watching list
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 16),
                ...continueWatching.take(5).map((rec) {
                  final item = rec.item;
                  final percentage = watchHistory[item.streamId.toString()]
                          is Map
                      ? (watchHistory[item.streamId.toString()]
                              as Map)['percentage'] as double? ??
                          0.0
                      : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: _ContinueWatchingCard(
                      item: item,
                      progress: percentage,
                      onTap: widget.onItemTap,
                    ),
                  );
                }),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  final Playlist item;
  final double progress;
  final VoidCallback? onTap;

  const _ContinueWatchingCard({
    required this.item,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster with progress bar
          Container(
            width: 160,
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[800],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: item.cover ?? '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[800],
                    ),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.image_not_supported,
                            color: Colors.grey[600]),
                  ),
                ),

                // Dark overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress / 100.0,
                            minHeight: 3,
                            backgroundColor: Colors.white30,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getProgressColor(progress),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${progress.toStringAsFixed(0)}% watched',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Play button overlay on hover
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Title
          SizedBox(
            width: 160,
            child: Text(
              item.name ?? 'Unknown',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress < 30) return Colors.red;
    if (progress < 70) return Colors.orange;
    return Colors.green;
  }
}

/// Widget showing trending/popular content
class TrendingWidget extends ConsumerWidget {
  final Playlist playlist;
  final List<Playlist> content;
  final VoidCallback? onItemTap;

  const TrendingWidget({
    Key? key,
    required this.playlist,
    required this.content,
    this.onItemTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingProvider);
    final trendingContent =
        RecommendationService.getTrending(trending, content);

    if (trendingContent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Trending Now',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 16),
                ...trendingContent.take(5).map((rec) {
                  final item = rec.item;
                  final rank = trendingContent.indexOf(rec) + 1;

                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: _TrendingCard(
                      item: item,
                      rank: rank,
                      onTap: onItemTap,
                    ),
                  );
                }),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final Playlist item;
  final int rank;
  final VoidCallback? onTap;

  const _TrendingCard({
    required this.item,
    required this.rank,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          // Card
          Container(
            width: 180,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[800],
            ),
            child: Column(
              children: [
                // Image
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item.cover ?? '',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[800],
                      ),
                      errorWidget: (context, url, error) =>
                          Icon(Icons.image_not_supported,
                              color: Colors.grey[600]),
                    ),
                  ),
                ),

                // Info
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.rating != null)
                        Row(
                          children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              item.rating ?? '0',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Rank badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              decoration: BoxDecoration(
                color: _getRankColor(rank),
                shape: BoxShape.circle,
              ),
              width: 40,
              height: 40,
              child: Center(
                child: Text(
                  '#$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.grey.shade600;
      case 3:
        return Colors.orange.shade700;
      default:
        return Colors.blue.shade700;
    }
  }
}

/// Widget showing recently added content
class RecentlyAddedWidget extends ConsumerWidget {
  final Playlist playlist;
  final List<Playlist> content;
  final VoidCallback? onItemTap;

  const RecentlyAddedWidget({
    Key? key,
    required this.playlist,
    required this.content,
    this.onItemTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = RecommendationService.getRecentlyAdded(content);

    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Recently Added',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 16),
                ...recent.take(5).map((rec) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: _RecentCard(
                      item: rec.item,
                      onTap: onItemTap,
                    ),
                  );
                }),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Playlist item;
  final VoidCallback? onTap;

  const _RecentCard({
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[800],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: item.cover ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey[800],
            ),
            errorWidget: (context, url, error) =>
                Icon(Icons.image_not_supported, color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}
