import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Streaming quality presets for Live TV
enum StreamQuality {
  low,    // 1.5 Mbps, CRF 26
  medium, // 3 Mbps, CRF 23
  high,   // 5 Mbps, CRF 20
}

/// Buffer size presets for Live TV
enum BufferSize {
  low,    // 2s segments, 4MB buffer
  medium, // 4s segments, 8MB buffer
  high,   // 6s segments, 12MB buffer
}

/// Connection timeout presets
enum ConnectionTimeout {
  short,  // 15 seconds
  medium, // 30 seconds
  long,   // 60 seconds
}

/// EPG cache duration presets
enum EpgCacheDuration {
  short,  // 5 minutes
  medium, // 15 minutes
  long,   // 60 minutes
}

/// Transcoding mode for Live TV
enum TranscodingMode {
  auto,     // Auto-detect best mode
  forced,   // Always transcode
  disabled, // Direct stream (no transcoding)
}

/// Keys for SharedPreferences storage
class _SettingsKeys {
  // Filters
  static const String liveTvFilter = 'filter_live_tv';
  static const String moviesFilter = 'filter_movies';
  static const String seriesFilter = 'filter_series';
  
  // Streaming settings
  static const String streamQuality = 'stream_quality';
  static const String bufferSize = 'buffer_size';
  static const String connectionTimeout = 'connection_timeout';
  static const String autoReconnect = 'auto_reconnect';
  static const String epgCacheDuration = 'epg_cache_duration';
  static const String transcodingMode = 'transcoding_mode';
  static const String preferDirectPlay = 'prefer_direct_play';
}

/// Settings state for IPTV preferences with persistence
class IptvSettings {
  // Category filters
  final String liveTvCategoryFilter;
  final String moviesCategoryFilter;
  final String seriesCategoryFilter;

  // Streaming settings (Live TV only)
  final StreamQuality streamQuality;
  final BufferSize bufferSize;
  final ConnectionTimeout connectionTimeout;
  final bool autoReconnect;
  final EpgCacheDuration epgCacheDuration;
  final TranscodingMode transcodingMode;
  final bool preferDirectPlay;

  const IptvSettings({
    // Filters
    this.liveTvCategoryFilter = '',
    this.moviesCategoryFilter = '',
    this.seriesCategoryFilter = '',
    // Streaming defaults
    this.streamQuality = StreamQuality.medium,
    this.bufferSize = BufferSize.medium,
    this.connectionTimeout = ConnectionTimeout.medium,
    this.autoReconnect = true,
    this.epgCacheDuration = EpgCacheDuration.medium,
    this.transcodingMode = TranscodingMode.auto,
    this.preferDirectPlay = false,
  });

  IptvSettings copyWith({
    String? liveTvCategoryFilter,
    String? moviesCategoryFilter,
    String? seriesCategoryFilter,
    StreamQuality? streamQuality,
    BufferSize? bufferSize,
    ConnectionTimeout? connectionTimeout,
    bool? autoReconnect,
    EpgCacheDuration? epgCacheDuration,
    TranscodingMode? transcodingMode,
    bool? preferDirectPlay,
  }) {
    return IptvSettings(
      liveTvCategoryFilter: liveTvCategoryFilter ?? this.liveTvCategoryFilter,
      moviesCategoryFilter: moviesCategoryFilter ?? this.moviesCategoryFilter,
      seriesCategoryFilter: seriesCategoryFilter ?? this.seriesCategoryFilter,
      streamQuality: streamQuality ?? this.streamQuality,
      bufferSize: bufferSize ?? this.bufferSize,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      epgCacheDuration: epgCacheDuration ?? this.epgCacheDuration,
      transcodingMode: transcodingMode ?? this.transcodingMode,
      preferDirectPlay: preferDirectPlay ?? this.preferDirectPlay,
    );
  }

  // ===== Streaming Value Getters =====

  /// Get bitrate in kbps based on quality setting
  int get bitrateKbps {
    switch (streamQuality) {
      case StreamQuality.low: return 1500;
      case StreamQuality.medium: return 3000;
      case StreamQuality.high: return 5000;
    }
  }

  /// Get CRF value based on quality setting
  int get crfValue {
    switch (streamQuality) {
      case StreamQuality.low: return 26;
      case StreamQuality.medium: return 23;
      case StreamQuality.high: return 20;
    }
  }

  /// Get HLS segment duration in seconds
  int get hlsSegmentDuration {
    switch (bufferSize) {
      case BufferSize.low: return 2;
      case BufferSize.medium: return 4;
      case BufferSize.high: return 6;
    }
  }

  /// Get buffer size in KB
  int get bufferSizeKb {
    switch (bufferSize) {
      case BufferSize.low: return 4000;
      case BufferSize.medium: return 8000;
      case BufferSize.high: return 12000;
    }
  }

  /// Get connection timeout in seconds
  int get timeoutSeconds {
    switch (connectionTimeout) {
      case ConnectionTimeout.short: return 15;
      case ConnectionTimeout.medium: return 30;
      case ConnectionTimeout.long: return 60;
    }
  }

  /// Get EPG cache duration in minutes
  int get epgCacheMinutes {
    switch (epgCacheDuration) {
      case EpgCacheDuration.short: return 5;
      case EpgCacheDuration.medium: return 15;
      case EpgCacheDuration.long: return 60;
    }
  }

  // ===== Filter Methods =====

  static List<String> _parseKeywords(String filter) {
    if (filter.isEmpty) return [];
    return filter
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> get liveTvKeywords => _parseKeywords(liveTvCategoryFilter);
  List<String> get moviesKeywords => _parseKeywords(moviesCategoryFilter);
  List<String> get seriesKeywords => _parseKeywords(seriesCategoryFilter);

  bool matchesLiveTvFilter(String categoryName) {
    return _matchesFilter(categoryName, liveTvKeywords);
  }

  bool matchesMoviesFilter(String categoryName) {
    return _matchesFilter(categoryName, moviesKeywords);
  }

  bool matchesSeriesFilter(String categoryName) {
    return _matchesFilter(categoryName, seriesKeywords);
  }

  bool _matchesFilter(String categoryName, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final upperName = categoryName.toUpperCase();
    return keywords.any((keyword) => upperName.contains(keyword));
  }

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
      
      // Load filters
      final liveTv = _prefs?.getString(_SettingsKeys.liveTvFilter) ?? '';
      final movies = _prefs?.getString(_SettingsKeys.moviesFilter) ?? '';
      final series = _prefs?.getString(_SettingsKeys.seriesFilter) ?? '';
      
      // Load streaming settings
      final quality = StreamQuality.values[
        _prefs?.getInt(_SettingsKeys.streamQuality) ?? StreamQuality.medium.index
      ];
      final buffer = BufferSize.values[
        _prefs?.getInt(_SettingsKeys.bufferSize) ?? BufferSize.medium.index
      ];
      final timeout = ConnectionTimeout.values[
        _prefs?.getInt(_SettingsKeys.connectionTimeout) ?? ConnectionTimeout.medium.index
      ];
      final reconnect = _prefs?.getBool(_SettingsKeys.autoReconnect) ?? true;
      final epgCache = EpgCacheDuration.values[
        _prefs?.getInt(_SettingsKeys.epgCacheDuration) ?? EpgCacheDuration.medium.index
      ];
      final transcoding = TranscodingMode.values[
        _prefs?.getInt(_SettingsKeys.transcodingMode) ?? TranscodingMode.auto.index
      ];
      final directPlay = _prefs?.getBool(_SettingsKeys.preferDirectPlay) ?? false;
      
      state = IptvSettings(
        liveTvCategoryFilter: liveTv,
        moviesCategoryFilter: movies,
        seriesCategoryFilter: series,
        streamQuality: quality,
        bufferSize: buffer,
        connectionTimeout: timeout,
        autoReconnect: reconnect,
        epgCacheDuration: epgCache,
        transcodingMode: transcoding,
        preferDirectPlay: directPlay,
      );
      
      _initialized = true;
      print('Settings loaded: LiveTV="$liveTv", Quality=${quality.name}');
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  // ===== Save Helpers =====

  Future<void> _saveString(String key, String value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(key, value);
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  Future<void> _saveInt(String key, int value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setInt(key, value);
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setBool(key, value);
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  // ===== Filter Setters =====

  void setLiveTvFilter(String filter) {
    state = state.copyWith(liveTvCategoryFilter: filter);
    _saveString(_SettingsKeys.liveTvFilter, filter);
  }

  void setMoviesFilter(String filter) {
    state = state.copyWith(moviesCategoryFilter: filter);
    _saveString(_SettingsKeys.moviesFilter, filter);
  }

  void setSeriesFilter(String filter) {
    state = state.copyWith(seriesCategoryFilter: filter);
    _saveString(_SettingsKeys.seriesFilter, filter);
  }

  void clearLiveTvFilter() => setLiveTvFilter('');
  void clearMoviesFilter() => setMoviesFilter('');
  void clearSeriesFilter() => setSeriesFilter('');

  void clearAllFilters() {
    clearLiveTvFilter();
    clearMoviesFilter();
    clearSeriesFilter();
  }

  // ===== Streaming Setters =====

  void setStreamQuality(StreamQuality quality) {
    state = state.copyWith(streamQuality: quality);
    _saveInt(_SettingsKeys.streamQuality, quality.index);
  }

  void setBufferSize(BufferSize buffer) {
    state = state.copyWith(bufferSize: buffer);
    _saveInt(_SettingsKeys.bufferSize, buffer.index);
  }

  void setConnectionTimeout(ConnectionTimeout timeout) {
    state = state.copyWith(connectionTimeout: timeout);
    _saveInt(_SettingsKeys.connectionTimeout, timeout.index);
  }

  void setAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
    _saveBool(_SettingsKeys.autoReconnect, value);
  }

  void setEpgCacheDuration(EpgCacheDuration duration) {
    state = state.copyWith(epgCacheDuration: duration);
    _saveInt(_SettingsKeys.epgCacheDuration, duration.index);
  }

  void setTranscodingMode(TranscodingMode mode) {
    state = state.copyWith(transcodingMode: mode);
    _saveInt(_SettingsKeys.transcodingMode, mode.index);
  }

  void setPreferDirectPlay(bool value) {
    state = state.copyWith(preferDirectPlay: value);
    _saveBool(_SettingsKeys.preferDirectPlay, value);
  }

  // Legacy methods
  void setCategoryFilter(String filter) => setLiveTvFilter(filter);
  void clearCategoryFilter() => clearLiveTvFilter();
}

/// Provider for IPTV settings
final iptvSettingsProvider =
    StateNotifierProvider<IptvSettingsNotifier, IptvSettings>((ref) {
  return IptvSettingsNotifier();
});
