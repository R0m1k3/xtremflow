import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/settings_api_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Streaming quality presets for Live TV
enum StreamQuality {
  low, // 1.5 Mbps, CRF 26
  medium, // 3 Mbps, CRF 23
  high, // 5 Mbps, CRF 20
}

/// Buffer size presets for Live TV
enum BufferSize {
  low, // 2s segments, 4MB buffer
  medium, // 4s segments, 8MB buffer
  high, // 6s segments, 12MB buffer
}

/// Connection timeout presets
enum ConnectionTimeout {
  short, // 15 seconds
  medium, // 30 seconds
  long, // 60 seconds
}

/// EPG cache duration presets
enum EpgCacheDuration {
  short, // 5 minutes
  medium, // 15 minutes
  long, // 60 minutes
}

/// Transcoding mode for Live TV
enum TranscodingMode {
  auto, // Auto-detect best mode
  forced, // Always transcode
  disabled, // Direct stream (no transcoding)
}

/// Player Type Preference
enum PlayerType {
  standard, // Heavily customized HTML5 player (default)
  lite, // Lightweight native/video_player based
}

/// Keys for API JSON storage
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
  static const String playerType = 'player_type';
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
  final PlayerType playerType;

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
    this.playerType = PlayerType.standard,
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
    PlayerType? playerType,
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
      playerType: playerType ?? this.playerType,
    );
  }

  // ===== Streaming Value Getters =====

  /// Get bitrate in kbps based on quality setting
  int get bitrateKbps {
    switch (streamQuality) {
      case StreamQuality.low:
        return 1500;
      case StreamQuality.medium:
        return 3000;
      case StreamQuality.high:
        return 5000;
    }
  }

  /// Get CRF value based on quality setting
  int get crfValue {
    switch (streamQuality) {
      case StreamQuality.low:
        return 26;
      case StreamQuality.medium:
        return 23;
      case StreamQuality.high:
        return 20;
    }
  }

  /// Get HLS segment duration in seconds
  int get hlsSegmentDuration {
    switch (bufferSize) {
      case BufferSize.low:
        return 2;
      case BufferSize.medium:
        return 4;
      case BufferSize.high:
        return 6;
    }
  }

  /// Get buffer size in KB
  int get bufferSizeKb {
    switch (bufferSize) {
      case BufferSize.low:
        return 4000;
      case BufferSize.medium:
        return 8000;
      case BufferSize.high:
        return 12000;
    }
  }

  /// Get connection timeout in seconds
  int get timeoutSeconds {
    switch (connectionTimeout) {
      case ConnectionTimeout.short:
        return 15;
      case ConnectionTimeout.medium:
        return 30;
      case ConnectionTimeout.long:
        return 60;
    }
  }

  /// Get EPG cache duration in minutes
  int get epgCacheMinutes {
    switch (epgCacheDuration) {
      case EpgCacheDuration.short:
        return 5;
      case EpgCacheDuration.medium:
        return 15;
      case EpgCacheDuration.long:
        return 60;
    }
  }

  /// Get transcoding mode string for FFmpeg URL parameter
  String get modeString {
    switch (transcodingMode) {
      case TranscodingMode.disabled:
        return 'direct'; // Passthrough, 0% CPU
      case TranscodingMode.forced:
        return 'transcode';
      case TranscodingMode.auto:
        return 'auto';
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

/// Settings notifier with API persistence only (No Local Cache)
class IptvSettingsNotifier extends StateNotifier<IptvSettings> {
  final SettingsApiService _apiService = SettingsApiService();
  final Ref _ref;
  // ignore: unused_field
  bool _initialized = false;

  IptvSettingsNotifier(this._ref) : super(const IptvSettings()) {
    _init();
    _setupAuthListener();
  }

  void _init() {
    final authState = _ref.read(authProvider);
    if (authState.isAuthenticated) {
      _fetchFromApi();
    }
  }

  void _setupAuthListener() {
    _ref.listen<AuthState>(authProvider, (previous, next) {
      // Sync on login
      if (previous?.isAuthenticated == false && next.isAuthenticated) {
        _fetchFromApi();
      }
      // Reset on logout
      if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        state = const IptvSettings();
        _initialized = false;
      }
    });
  }

  Future<void> _fetchFromApi() async {
    try {
      final remoteSettings = await _apiService.getSettings();
      if (remoteSettings != null && remoteSettings.isNotEmpty) {
        // Helper to safely cast dynamic types from JSON
        T? getValue<T>(String key) => remoteSettings[key] as T?;

        state = state.copyWith(
          liveTvCategoryFilter: getValue<String>(_SettingsKeys.liveTvFilter),
          moviesCategoryFilter: getValue<String>(_SettingsKeys.moviesFilter),
          seriesCategoryFilter: getValue<String>(_SettingsKeys.seriesFilter),
          streamQuality: remoteSettings[_SettingsKeys.streamQuality] != null
              ? StreamQuality
                  .values[remoteSettings[_SettingsKeys.streamQuality] as int]
              : null,
          bufferSize: remoteSettings[_SettingsKeys.bufferSize] != null
              ? BufferSize
                  .values[remoteSettings[_SettingsKeys.bufferSize] as int]
              : null,
          connectionTimeout:
              remoteSettings[_SettingsKeys.connectionTimeout] != null
                  ? ConnectionTimeout.values[
                      remoteSettings[_SettingsKeys.connectionTimeout] as int]
                  : null,
          autoReconnect: getValue<bool>(_SettingsKeys.autoReconnect),
          epgCacheDuration: remoteSettings[_SettingsKeys.epgCacheDuration] !=
                  null
              ? EpgCacheDuration
                  .values[remoteSettings[_SettingsKeys.epgCacheDuration] as int]
              : null,
          transcodingMode: remoteSettings[_SettingsKeys.transcodingMode] != null
              ? TranscodingMode
                  .values[remoteSettings[_SettingsKeys.transcodingMode] as int]
              : null,
          preferDirectPlay: getValue<bool>(_SettingsKeys.preferDirectPlay),
          showClock: getValue<bool>(_SettingsKeys.showClock),
          preferredAspectRatio:
              getValue<String>(_SettingsKeys.preferredAspectRatio),
          playerType: remoteSettings[_SettingsKeys.playerType] != null
              ? PlayerType
                  .values[remoteSettings[_SettingsKeys.playerType] as int]
              : null,
        );
      }
      _initialized = true;
    } catch (e) {
      print('Error syncing settings from API: $e');
    }
  }

  Timer? _saveDebounceTimer;

  @override
  void dispose() {
    _saveDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveToApi() async {
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated) {
      print('[SettingsProvider] _saveToApi: Not authenticated, skipping save');
      return;
    }

    // Cancel pending save
    _saveDebounceTimer?.cancel();

    // Debounce for 1 second to avoid rapid API calls
    _saveDebounceTimer = Timer(const Duration(seconds: 1), () async {
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
        _SettingsKeys.playerType: state.playerType.index,
      };

      print('[SettingsProvider] _saveToApi: Saving settings...');
      final success = await _apiService.saveSettings(settingsMap);
      print('[SettingsProvider] _saveToApi: Save result: $success');
    });
  }

  // ===== Setters with Auto-Save =====

  void setLiveTvFilter(String filter) {
    state = state.copyWith(liveTvCategoryFilter: filter);
    _saveToApi();
  }

  void setMoviesFilter(String filter) {
    state = state.copyWith(moviesCategoryFilter: filter);
    _saveToApi();
  }

  void setSeriesFilter(String filter) {
    state = state.copyWith(seriesCategoryFilter: filter);
    _saveToApi();
  }

  void clearLiveTvFilter() => setLiveTvFilter('');
  void clearMoviesFilter() => setMoviesFilter('');
  void clearSeriesFilter() => setSeriesFilter('');

  void clearAllFilters() {
    state = state.copyWith(
      liveTvCategoryFilter: '',
      moviesCategoryFilter: '',
      seriesCategoryFilter: '',
    );
    _saveToApi();
  }

  // ===== Streaming Setters =====

  void setStreamQuality(StreamQuality quality) {
    state = state.copyWith(streamQuality: quality);
    _saveToApi();
  }

  void setBufferSize(BufferSize buffer) {
    state = state.copyWith(bufferSize: buffer);
    _saveToApi();
  }

  void setConnectionTimeout(ConnectionTimeout timeout) {
    state = state.copyWith(connectionTimeout: timeout);
    _saveToApi();
  }

  void setAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value);
    _saveToApi();
  }

  void setEpgCacheDuration(EpgCacheDuration duration) {
    state = state.copyWith(epgCacheDuration: duration);
    _saveToApi();
  }

  void setTranscodingMode(TranscodingMode mode) {
    state = state.copyWith(transcodingMode: mode);
    _saveToApi();
  }

  void setPreferDirectPlay(bool value) {
    state = state.copyWith(preferDirectPlay: value);
    _saveToApi();
  }

  // ===== Player Display Setters =====

  void setShowClock(bool value) {
    state = state.copyWith(showClock: value);
    _saveToApi();
  }

  void setPreferredAspectRatio(String value) {
    state = state.copyWith(preferredAspectRatio: value);
    _saveToApi();
  }

  void setPlayerType(PlayerType type) {
    state = state.copyWith(playerType: type);
    _saveToApi();
  }

  // Legacy methods
  void setCategoryFilter(String filter) => setLiveTvFilter(filter);
  void clearCategoryFilter() => clearLiveTvFilter();
}

/// Provider for IPTV settings
final iptvSettingsProvider =
    StateNotifierProvider<IptvSettingsNotifier, IptvSettings>((ref) {
  // Watch auth provider to re-fetch settings on login/logout
  // We just watch it to ensure the provider tree updates, but the listener above handles logic
  ref.watch(authProvider);
  return IptvSettingsNotifier(ref);
});
