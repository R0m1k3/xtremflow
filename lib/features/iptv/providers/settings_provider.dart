import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/settings_api_service.dart';
import '../../auth/providers/auth_provider.dart';

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
  // Player Display Settings
  static const String showClock = 'show_clock';
  static const String preferredAspectRatio = 'aspect_ratio';
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
  
  // Player Display Settings
  final bool showClock;
  final String preferredAspectRatio;

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
    // Player defaults
    this.showClock = false,
    this.preferredAspectRatio = 'contain',
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
    bool? showClock,
    String? preferredAspectRatio,
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
      showClock: showClock ?? this.showClock,
      preferredAspectRatio: preferredAspectRatio ?? this.preferredAspectRatio,
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

  /// Get transcoding mode string for FFmpeg URL parameter
  String get modeString {
    switch (transcodingMode) {
      case TranscodingMode.disabled: return 'direct';  // Passthrough, 0% CPU
      case TranscodingMode.forced: return 'transcode';
      case TranscodingMode.auto: return 'auto';
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

/// IPTV Settings notifier with SharedPreferences and API persistence
class IptvSettingsNotifier extends StateNotifier<IptvSettings> {
  SharedPreferences? _prefs;
  final SettingsApiService _apiService = SettingsApiService();
  final Ref _ref;
  bool _initialized = false;

  IptvSettingsNotifier(this._ref) : super(const IptvSettings()) {
    _loadSettings();
  }

  /// Load settings from SharedPreferences and then API
  Future<void> _loadSettings() async {
    if (_initialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load local settings first (fastest)
      final liveTv = _prefs?.getString(_SettingsKeys.liveTvFilter) ?? '';
      final movies = _prefs?.getString(_SettingsKeys.moviesFilter) ?? '';
      final series = _prefs?.getString(_SettingsKeys.seriesFilter) ?? '';
      
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
      
      final showClock = _prefs?.getBool(_SettingsKeys.showClock) ?? false;
      final aspectRatio = _prefs?.getString(_SettingsKeys.preferredAspectRatio) ?? 'contain';

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
        showClock: showClock,
        preferredAspectRatio: aspectRatio,
      );
      
      _initialized = true;

      // Sync from API if logged in
      final authState = _ref.read(authProvider);
      if (authState.isAuthenticated) {
        await _fetchFromApi();
      }

    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _fetchFromApi() async {
    try {
      final remoteSettings = await _apiService.getSettings();
      if (remoteSettings != null && remoteSettings.isNotEmpty) {
        // Update state with remote settings if they exist
        T? getValue<T>(String key) => remoteSettings[key] as T?;

        state = state.copyWith(
          liveTvCategoryFilter: getValue<String>(_SettingsKeys.liveTvFilter),
          moviesCategoryFilter: getValue<String>(_SettingsKeys.moviesFilter),
          seriesCategoryFilter: getValue<String>(_SettingsKeys.seriesFilter),
          
          streamQuality: remoteSettings[_SettingsKeys.streamQuality] != null 
              ? StreamQuality.values[remoteSettings[_SettingsKeys.streamQuality] as int] : null,
          bufferSize: remoteSettings[_SettingsKeys.bufferSize] != null
              ? BufferSize.values[remoteSettings[_SettingsKeys.bufferSize] as int] : null,
          connectionTimeout: remoteSettings[_SettingsKeys.connectionTimeout] != null
              ? ConnectionTimeout.values[remoteSettings[_SettingsKeys.connectionTimeout] as int] : null,
          autoReconnect: getValue<bool>(_SettingsKeys.autoReconnect),
          epgCacheDuration: remoteSettings[_SettingsKeys.epgCacheDuration] != null
              ? EpgCacheDuration.values[remoteSettings[_SettingsKeys.epgCacheDuration] as int] : null,
          transcodingMode: remoteSettings[_SettingsKeys.transcodingMode] != null
              ? TranscodingMode.values[remoteSettings[_SettingsKeys.transcodingMode] as int] : null,
          preferDirectPlay: getValue<bool>(_SettingsKeys.preferDirectPlay),
          showClock: getValue<bool>(_SettingsKeys.showClock),
          preferredAspectRatio: getValue<String>(_SettingsKeys.preferredAspectRatio),
        );
        
        // Save to local prefs to keep in sync
        _saveToPrefs();
      }
    } catch (e) {
       print('Error syncing settings from API: $e');
    }
  }

  Future<void> _saveToApi() async {
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated) return;

    // Create map from state
    final settingsMap = {
      _SettingsKeys.liveTvFilter: state.liveTvCategoryFilter,
      _SettingsKeys.moviesFilter: state.moviesCategoryFilter,
      _SettingsKeys.seriesFilter: state.seriesCategoryFilter,
      _SettingsKeys.streamQuality: state.streamQuality.index,
      _SettingsKeys.bufferSize: state.bufferSize.index,
      _SettingsKeys.connectionTimeout: state.connectionTimeout.index,
      _SettingsKeys.autoReconnect: state.autoReconnect,
      _SettingsKeys.epgCacheDuration: state.epgCacheDuration.index,
      _SettingsKeys.transcodingMode: state.transcodingMode.index,
      _SettingsKeys.preferDirectPlay: state.preferDirectPlay,
      _SettingsKeys.showClock: state.showClock,
      _SettingsKeys.preferredAspectRatio: state.preferredAspectRatio,
    };

    await _apiService.saveSettings(settingsMap);
  }

  // ===== Save Helpers =====

  Future<void> _saveString(String key, String value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(key, value);
      await _saveToApi();
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  Future<void> _saveInt(String key, int value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setInt(key, value);
      await _saveToApi();
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setBool(key, value);
      await _saveToApi();
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  Future<void> _saveToPrefs() async {
     // Helper to bulk save state to prefs (after API fetch)
     _prefs ??= await SharedPreferences.getInstance();
     await _prefs?.setString(_SettingsKeys.liveTvFilter, state.liveTvCategoryFilter);
     await _prefs?.setString(_SettingsKeys.moviesFilter, state.moviesCategoryFilter);
     await _prefs?.setString(_SettingsKeys.seriesFilter, state.seriesCategoryFilter);
     
     await _prefs?.setInt(_SettingsKeys.streamQuality, state.streamQuality.index);
     await _prefs?.setInt(_SettingsKeys.bufferSize, state.bufferSize.index);
     await _prefs?.setInt(_SettingsKeys.connectionTimeout, state.connectionTimeout.index);
     await _prefs?.setBool(_SettingsKeys.autoReconnect, state.autoReconnect);
     await _prefs?.setInt(_SettingsKeys.epgCacheDuration, state.epgCacheDuration.index);
     await _prefs?.setInt(_SettingsKeys.transcodingMode, state.transcodingMode.index);
     await _prefs?.setBool(_SettingsKeys.preferDirectPlay, state.preferDirectPlay);
     
     await _prefs?.setBool(_SettingsKeys.showClock, state.showClock);
     await _prefs?.setString(_SettingsKeys.preferredAspectRatio, state.preferredAspectRatio);
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

  // ===== Player Display Setters =====

  void setShowClock(bool value) {
    state = state.copyWith(showClock: value);
    _saveBool(_SettingsKeys.showClock, value);
  }

  void setPreferredAspectRatio(String value) {
    state = state.copyWith(preferredAspectRatio: value);
    _saveString(_SettingsKeys.preferredAspectRatio, value);
  }

  // Legacy methods
  void setCategoryFilter(String filter) => setLiveTvFilter(filter);
  void clearCategoryFilter() => clearLiveTvFilter();
}

/// Provider for IPTV settings
final iptvSettingsProvider =
    StateNotifierProvider<IptvSettingsNotifier, IptvSettings>((ref) {
  // Watch auth provider to re-fetch settings on login/logout
  final authState = ref.watch(authProvider);
  final notifier = IptvSettingsNotifier(ref);
  
  // Note: Since we watch authProvider, this provider will be disposed and recreated
  // whenever authState changes. This automatically handles fetching settings for
  // the new user on creation.
  
  return notifier;
});
