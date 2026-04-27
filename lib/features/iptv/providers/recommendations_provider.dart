import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../models/playlist.dart';

/// Represents a content recommendation
class Recommendation {
  final Playlist item;
  final RecommendationType type;
  final double score;
  final String reason;

  Recommendation({
    required this.item,
    required this.type,
    this.score = 0.0,
    required this.reason,
  });
}

enum RecommendationType {
  continueWatching,
  trending,
  recentlyAdded,
  similarContent,
  topRated,
  forYou,
}

class RecommendationService {
  /// Get continue watching items based on watch history
  static List<Recommendation> getContinueWatching(
    Map<String, dynamic> watchHistory,
    List<Playlist> allContent,
  ) {
    final recommendations = <Recommendation>[];

    for (final item in allContent) {
      final historyKey = item.streamId.toString();
      if (watchHistory.containsKey(historyKey)) {
        final lastPosition = watchHistory[historyKey] as double? ?? 0.0;

        // Only show if watched more than 5 seconds ago and less than 95% complete
        if (lastPosition > 5 && lastPosition < 95) {
          recommendations.add(
            Recommendation(
              item: item,
              type: RecommendationType.continueWatching,
              score: 100.0 - lastPosition, // Score higher if recently started
              reason:
                  'Continue watching from ${lastPosition.toStringAsFixed(0)}%',
            ),
          );
        }
      }
    }

    // Sort by last watched (highest incomplete progress first)
    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(10).toList();
  }

  /// Get trending content based on view counts
  static List<Recommendation> getTrending(
    Map<String, int> viewCounts,
    List<Playlist> allContent,
  ) {
    final recommendations = <Recommendation>[];

    for (final item in allContent) {
      final views = viewCounts[item.streamId.toString()] ?? 0;
      if (views > 0) {
        recommendations.add(
          Recommendation(
            item: item,
            type: RecommendationType.trending,
            score: views.toDouble(),
            reason: '$views views - Trending now',
          ),
        );
      }
    }

    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(10).toList();
  }

  /// Get recently added content
  static List<Recommendation> getRecentlyAdded(List<Playlist> allContent) {
    final recommendations = <Recommendation>[];

    // Sort by added date (most recent first)
    final sorted = [...allContent];
    sorted.sort((a, b) {
      final aDate = DateTime.tryParse(a.added ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b.added ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    for (final item in sorted.take(20)) {
      final daysAgo = DateTime.now()
          .difference(DateTime.tryParse(item.added ?? '') ?? DateTime(2000))
          .inDays;

      recommendations.add(
        Recommendation(
          item: item,
          type: RecommendationType.recentlyAdded,
          score: (20 - daysAgo).toDouble().clamp(0, 100),
          reason: 'Added $daysAgo days ago',
        ),
      );
    }

    return recommendations.take(10).toList();
  }

  /// Get personalized recommendations based on watch history
  static List<Recommendation> getForYou(
    Map<String, dynamic> watchHistory,
    List<Playlist> allContent,
  ) {
    final recommendations = <Recommendation>[];

    // Collect watched categories
    final watchedCategories = <String>{};
    watchHistory.forEach((key, value) {
      if (value is Map && value.containsKey('category')) {
        watchedCategories.add(value['category'] as String);
      }
    });

    // Recommend similar content
    for (final item in allContent) {
      if (watchedCategories.contains(item.categoryId)) {
        recommendations.add(
          Recommendation(
            item: item,
            type: RecommendationType.forYou,
            score: 75.0,
            reason: 'Based on your interests',
          ),
        );
      }
    }

    // Add highly rated content
    var ratedContent = [...allContent];
    ratedContent.sort((a, b) {
      final aRating = double.tryParse(a.rating ?? '0') ?? 0.0;
      final bRating = double.tryParse(b.rating ?? '0') ?? 0.0;
      return bRating.compareTo(aRating);
    });

    for (final item in ratedContent.where((i) {
      final rating = double.tryParse(i.rating ?? '0') ?? 0.0;
      return rating >= 7.5;
    }).take(5)) {
      recommendations.add(
        Recommendation(
          item: item,
          type: RecommendationType.topRated,
          score: double.tryParse(item.rating ?? '0') ?? 0.0,
          reason: 'Highly rated - ${item.rating}/10',
        ),
      );
    }

    // Remove duplicates and limit
    final seen = <int>{};
    final unique = <Recommendation>[];
    for (final rec in recommendations) {
      if (!seen.contains(rec.item.streamId)) {
        unique.add(rec);
        seen.add(rec.item.streamId);
      }
    }

    return unique.take(15).toList();
  }
}

/// Provider for watch history
final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, Map<String, dynamic>>((ref) {
  return WatchHistoryNotifier();
});

class WatchHistoryNotifier extends StateNotifier<Map<String, dynamic>> {
  WatchHistoryNotifier() : super({});

  void updateWatchTime(int streamId, double percentage) {
    state = {
      ...state,
      streamId.toString(): {
        'percentage': percentage,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
  }

  void clearHistory() {
    state = {};
  }
}

/// Provider for view counts/trending
final trendingProvider =
    StateNotifierProvider<TrendingNotifier, Map<String, int>>((ref) {
  return TrendingNotifier();
});

class TrendingNotifier extends StateNotifier<Map<String, int>> {
  TrendingNotifier() : super({});

  void incrementViewCount(int streamId) {
    final key = streamId.toString();
    state = {
      ...state,
      key: (state[key] ?? 0) + 1,
    };
  }
}

/// Provider for recommendations
final recommendationsProvider = FutureProvider.family<List<Recommendation>,
    (Playlist, Map<String, dynamic>, Map<String, int>, List<Playlist>)>(
  (ref, params) async {
    final (playlist, watchHistory, trending, allContent) = params;

    // Combine all recommendation types
    final allRecommendations = <Recommendation>[
      ...RecommendationService.getContinueWatching(watchHistory, allContent),
      ...RecommendationService.getTrending(trending, allContent),
      ...RecommendationService.getRecentlyAdded(allContent),
      ...RecommendationService.getForYou(watchHistory, allContent),
    ];

    // Deduplicate and score
    final seen = <int>{};
    final scored = <Recommendation>[];

    for (final rec in allRecommendations) {
      if (!seen.contains(rec.item.streamId)) {
        scored.add(rec);
        seen.add(rec.item.streamId);
      }
    }

    // Sort by score
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  },
);
