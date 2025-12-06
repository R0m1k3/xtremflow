import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Watch history state - tracks which content has been watched
class WatchHistory {
  /// Set of watched movie IDs
  final Set<String> watchedMovies;
  
  /// Set of watched episode IDs (format: seriesId_seasonNum_episodeNum)
  final Set<String> watchedEpisodes;

  const WatchHistory({
    this.watchedMovies = const {},
    this.watchedEpisodes = const {},
  });

  WatchHistory copyWith({
    Set<String>? watchedMovies,
    Set<String>? watchedEpisodes,
  }) {
    return WatchHistory(
      watchedMovies: watchedMovies ?? this.watchedMovies,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
    );
  }

  /// Check if a movie has been watched
  bool isMovieWatched(String movieId) => watchedMovies.contains(movieId);

  /// Check if an episode has been watched
  bool isEpisodeWatched(String episodeId) => watchedEpisodes.contains(episodeId);
  
  /// Generate episode key
  static String episodeKey(int seriesId, int seasonNum, int episodeNum) {
    return '${seriesId}_${seasonNum}_$episodeNum';
  }
}

/// Watch history notifier with persistence
class WatchHistoryNotifier extends StateNotifier<WatchHistory> {
  static const String _moviesKey = 'watch_history_movies';
  static const String _episodesKey = 'watch_history_episodes';
  
  SharedPreferences? _prefs;
  bool _initialized = false;

  WatchHistoryNotifier() : super(const WatchHistory()) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_initialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      final moviesJson = _prefs?.getString(_moviesKey);
      final episodesJson = _prefs?.getString(_episodesKey);
      
      final movies = moviesJson != null
          ? Set<String>.from(jsonDecode(moviesJson) as List)
          : <String>{};
      
      final episodes = episodesJson != null
          ? Set<String>.from(jsonDecode(episodesJson) as List)
          : <String>{};
      
      state = WatchHistory(
        watchedMovies: movies,
        watchedEpisodes: episodes,
      );
      
      _initialized = true;
      print('Watch history loaded: ${movies.length} movies, ${episodes.length} episodes');
    } catch (e) {
      print('Error loading watch history: $e');
    }
  }

  Future<void> _saveMovies() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_moviesKey, jsonEncode(state.watchedMovies.toList()));
    } catch (e) {
      print('Error saving movie watch history: $e');
    }
  }

  Future<void> _saveEpisodes() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_episodesKey, jsonEncode(state.watchedEpisodes.toList()));
    } catch (e) {
      print('Error saving episode watch history: $e');
    }
  }

  /// Mark a movie as watched
  void markMovieWatched(String movieId) {
    final newSet = Set<String>.from(state.watchedMovies)..add(movieId);
    state = state.copyWith(watchedMovies: newSet);
    _saveMovies();
  }

  /// Mark a movie as unwatched
  void markMovieUnwatched(String movieId) {
    final newSet = Set<String>.from(state.watchedMovies)..remove(movieId);
    state = state.copyWith(watchedMovies: newSet);
    _saveMovies();
  }

  /// Toggle movie watched status
  void toggleMovieWatched(String movieId) {
    if (state.isMovieWatched(movieId)) {
      markMovieUnwatched(movieId);
    } else {
      markMovieWatched(movieId);
    }
  }

  /// Mark an episode as watched
  void markEpisodeWatched(String episodeKey) {
    final newSet = Set<String>.from(state.watchedEpisodes)..add(episodeKey);
    state = state.copyWith(watchedEpisodes: newSet);
    _saveEpisodes();
  }

  /// Mark an episode as unwatched
  void markEpisodeUnwatched(String episodeKey) {
    final newSet = Set<String>.from(state.watchedEpisodes)..remove(episodeKey);
    state = state.copyWith(watchedEpisodes: newSet);
    _saveEpisodes();
  }

  /// Toggle episode watched status
  void toggleEpisodeWatched(String episodeKey) {
    if (state.isEpisodeWatched(episodeKey)) {
      markEpisodeUnwatched(episodeKey);
    } else {
      markEpisodeWatched(episodeKey);
    }
  }

  /// Clear all watch history
  void clearAll() {
    state = const WatchHistory();
    _saveMovies();
    _saveEpisodes();
  }
}

/// Provider for watch history
final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, WatchHistory>((ref) {
  return WatchHistoryNotifier();
});
