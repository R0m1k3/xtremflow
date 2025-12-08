import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Playback position state - tracks resume positions for movies and episodes
class PlaybackPositions {
  /// Map of content ID to position in seconds (for movies: streamId, for episodes: seriesId_seasonNum_episodeNum)
  final Map<String, double> positions;

  const PlaybackPositions({
    this.positions = const {},
  });

  PlaybackPositions copyWith({
    Map<String, double>? positions,
  }) {
    return PlaybackPositions(
      positions: positions ?? this.positions,
    );
  }

  /// Get saved position for a content (returns 0 if not found)
  double getPosition(String contentId) => positions[contentId] ?? 0;

  /// Check if content has a saved position (beyond 30 seconds)
  bool hasPosition(String contentId) => (positions[contentId] ?? 0) > 30;
}

/// Playback positions notifier with persistence
class PlaybackPositionsNotifier extends StateNotifier<PlaybackPositions> {
  static const String _storageKey = 'playback_positions';
  
  SharedPreferences? _prefs;
  bool _initialized = false;

  PlaybackPositionsNotifier() : super(const PlaybackPositions()) {
    _loadPositions();
  }

  Future<void> _loadPositions() async {
    if (_initialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      final positionsJson = _prefs?.getString(_storageKey);
      
      if (positionsJson != null) {
        final decoded = jsonDecode(positionsJson) as Map<String, dynamic>;
        final positions = decoded.map((key, value) => 
          MapEntry(key, (value as num).toDouble()),
        );
        
        state = PlaybackPositions(positions: positions);
        print('Playback positions loaded: ${positions.length} entries');
      }
      
      _initialized = true;
    } catch (e) {
      print('Error loading playback positions: $e');
    }
  }

  Future<void> _savePositions() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_storageKey, jsonEncode(state.positions));
    } catch (e) {
      print('Error saving playback positions: $e');
    }
  }

  /// Save position for a content
  void savePosition(String contentId, double positionSeconds, double durationSeconds) {
    // Don't save if less than 30 seconds in or more than 95% complete
    if (positionSeconds < 30 || (durationSeconds > 0 && positionSeconds / durationSeconds > 0.95)) {
      // If 95% complete, remove any saved position (mark as fully watched)
      if (durationSeconds > 0 && positionSeconds / durationSeconds > 0.95) {
        clearPosition(contentId);
      }
      return;
    }
    
    final newPositions = Map<String, double>.from(state.positions);
    newPositions[contentId] = positionSeconds;
    state = state.copyWith(positions: newPositions);
    _savePositions();
  }

  /// Clear position for a content
  void clearPosition(String contentId) {
    final newPositions = Map<String, double>.from(state.positions);
    newPositions.remove(contentId);
    state = state.copyWith(positions: newPositions);
    _savePositions();
  }

  /// Clear all positions
  void clearAll() {
    state = const PlaybackPositions();
    _savePositions();
  }

  /// Get formatted resume time
  static String formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    if (mins >= 60) {
      final hours = (mins / 60).floor();
      final remainingMins = mins % 60;
      return '${hours}h ${remainingMins}m';
    }
    return '${mins}m ${secs}s';
  }
}

/// Provider for playback positions
final playbackPositionsProvider =
    StateNotifierProvider<PlaybackPositionsNotifier, PlaybackPositions>((ref) {
  return PlaybackPositionsNotifier();
});
