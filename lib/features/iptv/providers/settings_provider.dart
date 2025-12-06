import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for SharedPreferences storage
class _SettingsKeys {
  static const String liveTvFilter = 'filter_live_tv';
  static const String moviesFilter = 'filter_movies';
  static const String seriesFilter = 'filter_series';
}

/// Settings state for IPTV preferences with persistence
class IptvSettings {
  /// Category filter keywords for Live TV (comma-separated)
  final String liveTvCategoryFilter;
  
  /// Category filter keywords for Movies (comma-separated)
  final String moviesCategoryFilter;
  
  /// Category filter keywords for Series (comma-separated)
  final String seriesCategoryFilter;

  const IptvSettings({
    this.liveTvCategoryFilter = '',
    this.moviesCategoryFilter = '',
    this.seriesCategoryFilter = '',
  });

  IptvSettings copyWith({
    String? liveTvCategoryFilter,
    String? moviesCategoryFilter,
    String? seriesCategoryFilter,
  }) {
    return IptvSettings(
      liveTvCategoryFilter: liveTvCategoryFilter ?? this.liveTvCategoryFilter,
      moviesCategoryFilter: moviesCategoryFilter ?? this.moviesCategoryFilter,
      seriesCategoryFilter: seriesCategoryFilter ?? this.seriesCategoryFilter,
    );
  }

  /// Get list of filter keywords for a given filter string
  static List<String> _parseKeywords(String filter) {
    if (filter.isEmpty) return [];
    return filter
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Get live TV filter keywords
  List<String> get liveTvKeywords => _parseKeywords(liveTvCategoryFilter);
  
  /// Get movies filter keywords
  List<String> get moviesKeywords => _parseKeywords(moviesCategoryFilter);
  
  /// Get series filter keywords
  List<String> get seriesKeywords => _parseKeywords(seriesCategoryFilter);

  /// Check if a category name matches the Live TV filter
  bool matchesLiveTvFilter(String categoryName) {
    return _matchesFilter(categoryName, liveTvKeywords);
  }

  /// Check if a category name matches the Movies filter
  bool matchesMoviesFilter(String categoryName) {
    return _matchesFilter(categoryName, moviesKeywords);
  }

  /// Check if a category name matches the Series filter
  bool matchesSeriesFilter(String categoryName) {
    return _matchesFilter(categoryName, seriesKeywords);
  }

  /// Generic filter matching
  bool _matchesFilter(String categoryName, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final upperName = categoryName.toUpperCase();
    return keywords.any((keyword) => upperName.contains(keyword));
  }

  /// Legacy method for backwards compatibility
  bool matchesFilter(String categoryName) => matchesLiveTvFilter(categoryName);
}

/// IPTV Settings notifier with SharedPreferences persistence
class IptvSettingsNotifier extends StateNotifier<IptvSettings> {
  SharedPreferences? _prefs;
  bool _initialized = false;

  IptvSettingsNotifier() : super(const IptvSettings()) {
    _loadSettings();
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    if (_initialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      final liveTv = _prefs?.getString(_SettingsKeys.liveTvFilter) ?? '';
      final movies = _prefs?.getString(_SettingsKeys.moviesFilter) ?? '';
      final series = _prefs?.getString(_SettingsKeys.seriesFilter) ?? '';
      
      state = IptvSettings(
        liveTvCategoryFilter: liveTv,
        moviesCategoryFilter: movies,
        seriesCategoryFilter: series,
      );
      
      _initialized = true;
      print('Settings loaded: LiveTV="$liveTv", Movies="$movies", Series="$series"');
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  /// Save a setting to SharedPreferences
  Future<void> _saveString(String key, String value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(key, value);
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  /// Set Live TV category filter
  void setLiveTvFilter(String filter) {
    state = state.copyWith(liveTvCategoryFilter: filter);
    _saveString(_SettingsKeys.liveTvFilter, filter);
  }

  /// Set Movies category filter
  void setMoviesFilter(String filter) {
    state = state.copyWith(moviesCategoryFilter: filter);
    _saveString(_SettingsKeys.moviesFilter, filter);
  }

  /// Set Series category filter
  void setSeriesFilter(String filter) {
    state = state.copyWith(seriesCategoryFilter: filter);
    _saveString(_SettingsKeys.seriesFilter, filter);
  }

  /// Clear Live TV filter
  void clearLiveTvFilter() => setLiveTvFilter('');
  
  /// Clear Movies filter
  void clearMoviesFilter() => setMoviesFilter('');
  
  /// Clear Series filter
  void clearSeriesFilter() => setSeriesFilter('');

  /// Clear all filters
  void clearAllFilters() {
    clearLiveTvFilter();
    clearMoviesFilter();
    clearSeriesFilter();
  }

  // Legacy methods for backwards compatibility
  void setCategoryFilter(String filter) => setLiveTvFilter(filter);
  void clearCategoryFilter() => clearLiveTvFilter();
}

/// Provider for IPTV settings
final iptvSettingsProvider =
    StateNotifierProvider<IptvSettingsNotifier, IptvSettings>((ref) {
  return IptvSettingsNotifier();
});
