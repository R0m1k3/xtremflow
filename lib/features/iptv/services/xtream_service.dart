import 'dart:convert';
import 'dart:html' as html;
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../models/xtream_models.dart' as xm;

/// Xtream Codes API Service
///
/// Handles all communication with Xtream API servers
class XtreamService {
  late final Dio _dio;
  late final CacheOptions _cacheOptions;

  PlaylistConfig? _currentPlaylist;

  /// Flag to indicate that a playback is currently loading
  /// Used to throttle background requests (EPG, images)
  bool isPlaybackLoading = false;

  /// Minimum delay for background requests when playback is loading
  static const _throttleDelay = Duration(seconds: 8);

  XtreamService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    // Setup caching for API responses
    // Use MemCacheStore for in-memory caching
    _cacheOptions = CacheOptions(
      store: MemCacheStore(),
      policy: CachePolicy.forceCache, // Prioritize local cache
      maxStale: const Duration(hours: 1), // Increase to 1h for stability
      priority: CachePriority.high,
    );

    _dio.interceptors.add(DioCacheInterceptor(options: _cacheOptions));
  }

  String? _manualBackendUrl;

  /// Get dynamic base URL for the local backend
  /// Priority:
  /// 1. Manual override from settings
  /// 2. Detected origin (Web)
  /// 3. Host machine IP (Emulator)
  String get _backendBaseUrl {
    if (_manualBackendUrl != null && _manualBackendUrl!.isNotEmpty) {
      return _manualBackendUrl!;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      // If we are developing locally on a different port than the backend
      if (origin.contains('localhost') && !origin.contains('8089')) {
        return 'http://localhost:8089';
      }
      // On mobile devices, 'localhost' is the device itself.
      // If origin is localhost but we are on mobile web, it might fail.
      // We assume the user is accessing via an IP or hostname.
      return origin;
    }
    // Android emulator bridge
    return 'http://10.0.2.2:8089';
  }

  String get backendBaseUrl => _backendBaseUrl;

  /// Set manual backend URL override
  void setBackendUrl(String? url) {
    _manualBackendUrl = url;
  }

  /// Update connection timeouts
  void updateTimeouts(int seconds) {
    _dio.options.connectTimeout = Duration(seconds: seconds);
    _dio.options.receiveTimeout = Duration(seconds: seconds);
    _dio.options.sendTimeout = Duration(seconds: seconds);
  }

  /// Wrap URL with proxy for all external IPTV URLs
  String _wrapWithProxy(String url) {
    if (url.startsWith('http')) {
      return '$_backendBaseUrl/api/xtream/$url';
    }
    return url;
  }

  /// Initialize connection with a playlist
  void setPlaylist(PlaylistConfig playlist) {
    _currentPlaylist = playlist;
  }

  /// Generate stream URL for live TV (HLS)
  String getLiveStreamUrl(String streamId) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/live/$streamId/playlist.m3u8';
  }

  /// Generate stream URL for live TV (Direct MPEG-TS)
  /// Faster zapping on compatible players (mpegts.js)
  String getLiveStreamUrlTs(String streamId) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    // Direct link to the .ts stream through our proxy
    final dns = _currentPlaylist!.dns;
    final user = _currentPlaylist!.username;
    final pass = _currentPlaylist!.password;
    final url = '$dns/live/$user/$pass/$streamId.ts';
    return '$_backendBaseUrl/api/xtream/${Uri.encodeComponent(url)}';
  }

  /// Generate stream URL for VOD (movies)
  String getVodStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/vod/$streamId/playlist.m3u8';
  }

  /// Generate stream URL for series episodes
  String getSeriesStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/vod/$streamId/playlist.m3u8?type=series';
  }

  /// Authenticate and get server info
  Future<Map<String, dynamic>> authenticate() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  /// Load categories mapping (category_id -> category_name)
  Future<Map<String, String>> _getLiveCategories() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_live_categories',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) {
          categoryMap[id] = name;
        }
      }

      return categoryMap;
    } catch (e) {
      return {}; // Return empty map on error, channels will be "Uncategorized"
    }
  }

  /// Get all live TV channels grouped by category
  ///
  /// Returns a Map where key is category name and value is list of channels
  Future<Map<String, List<Channel>>> getLiveChannels({bool refresh = false}) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    final options = refresh 
        ? _cacheOptions.copyWith(policy: CachePolicy.refreshForceCache).toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize categories and streams fetching
      final results = await Future.wait([
        _getLiveCategories(),
        _dio.get(
          _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
          queryParameters: {
            'username': _currentPlaylist!.username,
            'password': _currentPlaylist!.password,
            'action': 'get_live_streams',
          },
          options: Options(extra: options),
        ),
      ]);

      final categoryMap = results[0] as Map<String, String>;
      final response = results[1] as Response;
      final List<dynamic> streams = response.data as List<dynamic>;
      final groupedChannels = <String, List<Channel>>{};

      for (final streamData in streams) {
        final data = streamData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        data['category_name'] = categoryName;

        final channel = Channel.fromJson(data);
        groupedChannels.putIfAbsent(categoryName, () => []).add(channel);
      }

      // Save to local cache for instant display next time
      _saveToLocalCache('live_channels', groupedChannels);

      return groupedChannels;
    } catch (e) {
      // Try to return from local cache if network fails
      final cached = _loadFromLocalCache<Channel>('live_channels', Channel.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch live channels: $e');
    }
  }

  void _saveToLocalCache(String key, Map<String, dynamic> data) {
    if (!kIsWeb) return;
    try {
      final jsonStr = jsonEncode(data);
      html.window.localStorage['xtream_cache_${_currentPlaylist?.id}_$key'] = jsonStr;
    } catch (e) {
      debugPrint('Error saving to local cache ($key): $e');
    }
  }

  Map<String, List<T>> _loadFromLocalCache<T>(
      String key, T Function(Map<String, dynamic>) fromJson) {
    if (!kIsWeb) return {};
    try {
      final jsonStr = html.window.localStorage['xtream_cache_${_currentPlaylist?.id}_$key'];
      if (jsonStr == null) return {};
      
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final result = <String, List<T>>{};
      
      data.forEach((cat, items) {
        if (items is List) {
          result[cat] = items
              .map((i) => fromJson(i as Map<String, dynamic>))
              .toList();
        }
      });
      return result;
    } catch (e) {
      debugPrint('Error loading from local cache ($key): $e');
      return {};
    }
  }

  /// Load VOD categories mapping
  Future<Map<String, String>> _getVodCategories() async {
    if (_currentPlaylist == null) return {};

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_categories',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) categoryMap[id] = name;
      }

      return categoryMap;
    } catch (e) {
      return {};
    }
  }

  /// Get all VOD items (movies) grouped by category
  Future<Map<String, List<VodItem>>> getVodItems({bool refresh = false}) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    final options = refresh 
        ? _cacheOptions.copyWith(policy: CachePolicy.refreshForceCache).toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize VOD categories and streams fetching
      final results = await Future.wait([
        _getVodCategories(),
        _dio.get(
          _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
          queryParameters: {
            'username': _currentPlaylist!.username,
            'password': _currentPlaylist!.password,
            'action': 'get_vod_streams',
          },
          options: Options(extra: options),
        ),
      ]);

      final categoryMap = results[0] as Map<String, String>;
      final response = results[1] as Response;

      final List<dynamic> vods = response.data as List<dynamic>;
      final Map<String, List<VodItem>> groupedVods = {};

      for (final vodData in vods) {
        final data = vodData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        data['category_name'] = categoryName;

        final vod = VodItem.fromJson(data);
        groupedVods.putIfAbsent(categoryName, () => []).add(vod);
      }

      // Save to local cache
      _saveToLocalCache('vod_items', groupedVods);

      return groupedVods;
    } catch (e) {
      // Try to return from local cache if network fails
      final cached = _loadFromLocalCache<VodItem>('vod_items', VodItem.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch VOD items: $e');
    }
  }

  /// Load Series categories mapping
  Future<Map<String, String>> _getSeriesCategories() async {
    if (_currentPlaylist == null) return {};

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series_categories',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) categoryMap[id] = name;
      }

      return categoryMap;
    } catch (e) {
      return {};
    }
  }

  /// Get all series grouped by category
  Future<Map<String, List<Series>>> getSeries({bool refresh = false}) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    final options = refresh 
        ? _cacheOptions.copyWith(policy: CachePolicy.refreshForceCache).toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize Series categories and streams fetching
      final results = await Future.wait([
        _getSeriesCategories(),
        _dio.get(
          _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
          queryParameters: {
            'username': _currentPlaylist!.username,
            'password': _currentPlaylist!.password,
            'action': 'get_series',
          },
          options: Options(extra: options),
        ),
      ]);

      final categoryMap = results[0] as Map<String, String>;
      final response = results[1] as Response;

      final List<dynamic> seriesList = response.data as List<dynamic>;
      final Map<String, List<Series>> groupedSeries = {};

      for (final seriesData in seriesList) {
        final data = seriesData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        data['category_name'] = categoryName;

        final series = Series.fromJson(data);
        groupedSeries.putIfAbsent(categoryName, () => []).add(series);
      }

      // Save to local cache
      _saveToLocalCache('series_items', groupedSeries);

      return groupedSeries;
    } catch (e) {
      // Try to return from local cache if network fails
      final cached = _loadFromLocalCache<Series>('series_items', Series.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch series: $e');
    }
  }

  /// Get movies with pagination support
  Future<List<xm.Movie>> getMoviesPaginated(
      {int offset = 0, int limit = 100}) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load categories for mapping
      final categoryMap = await _getVodCategories();

      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_streams',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> allMovies = response.data as List<dynamic>;

      // Apply pagination
      final endIndex = (offset + limit) > allMovies.length
          ? allMovies.length
          : offset + limit;
      if (offset >= allMovies.length) return [];

      final paginatedMovies = allMovies.sublist(offset, endIndex);

      return paginatedMovies.map((movieData) {
        final data = movieData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
        return xm.Movie.fromJson(data);
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch movies: $e');
    }
  }

  /// Search movies in the entire catalogue
  Future<List<xm.Movie>> searchMovies(String query) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    if (query.isEmpty) return [];

    try {
      final categoryMap = await _getVodCategories();

      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_streams',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> allMovies = response.data as List<dynamic>;
      final queryLower = query.toLowerCase();

      // Filter by search query
      return allMovies
          .where((m) {
            final name = (m['name']?.toString() ?? '').toLowerCase();
            return name.contains(queryLower);
          })
          .take(100) // Limit results
          .map((movieData) {
            final data = movieData as Map<String, dynamic>;
            final categoryId = data['category_id']?.toString() ?? '';
            data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
            return xm.Movie.fromJson(data);
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get series with pagination support (returns flat list)
  Future<List<xm.Series>> getSeriesPaginated(
      {int offset = 0, int limit = 100}) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load categories for mapping
      final categoryMap = await _getSeriesCategories();

      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> allSeries = response.data as List<dynamic>;

      // Apply pagination
      final endIndex = (offset + limit) > allSeries.length
          ? allSeries.length
          : offset + limit;
      if (offset >= allSeries.length) return [];

      final paginatedSeries = allSeries.sublist(offset, endIndex);

      return paginatedSeries.map((seriesData) {
        final data = seriesData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
        return xm.Series.fromJson(data);
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch series: $e');
    }
  }

  /// Search series in the entire catalogue
  Future<List<xm.Series>> searchSeries(String query) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    if (query.isEmpty) return [];

    try {
      final categoryMap = await _getSeriesCategories();

      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> allSeries = response.data as List<dynamic>;
      final queryLower = query.toLowerCase();

      // Filter by search query
      return allSeries
          .where((s) {
            final name = (s['name']?.toString() ?? '').toLowerCase();
            return name.contains(queryLower);
          })
          .take(100) // Limit results
          .map((seriesData) {
            final data = seriesData as Map<String, dynamic>;
            final categoryId = data['category_id']?.toString() ?? '';
            data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
            return xm.Series.fromJson(data);
          })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get series info with seasons and episodes
  Future<xm.SeriesInfo> getSeriesInfo(String seriesId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      return xm.SeriesInfo.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to fetch series info: $e');
    }
  }

  /// Get VOD (movie) info including duration
  ///
  /// Returns detailed movie information including duration in seconds
  Future<int?> getVodDuration(String vodId) async {
    if (_currentPlaylist == null) return null;

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_info',
          'vod_id': vodId,
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final data = response.data as Map<String, dynamic>;

      // Try to get duration from movie_properties or info
      final movieData = data['movie_data'] as Map<String, dynamic>?;
      final info = data['info'] as Map<String, dynamic>?;

      // Duration can be in different formats: seconds (int), "HH:MM:SS", or minutes
      String? durationStr = movieData?['duration']?.toString() ??
          info?['duration']?.toString() ??
          info?['duration_secs']?.toString();

      if (durationStr == null || durationStr.isEmpty) return null;

      // Parse duration - could be "01:30:00" format or seconds
      if (durationStr.contains(':')) {
        // HH:MM:SS format
        final parts = durationStr.split(':');
        if (parts.length == 3) {
          final hours = int.tryParse(parts[0]) ?? 0;
          final minutes = int.tryParse(parts[1]) ?? 0;
          final seconds = int.tryParse(parts[2]) ?? 0;
          return hours * 3600 + minutes * 60 + seconds;
        } else if (parts.length == 2) {
          // MM:SS format
          final minutes = int.tryParse(parts[0]) ?? 0;
          final seconds = int.tryParse(parts[1]) ?? 0;
          return minutes * 60 + seconds;
        }
      }

      // Try parsing as seconds directly
      return int.tryParse(durationStr);
    } catch (e) {
      // Duration is optional, don't fail
      return null;
    }
  }

  /// Get short EPG for a specific stream
  ///
  /// Returns "Now" and "Next" program info
  Future<List<EpgEntry>> getShortEpg(String streamId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    if (isPlaybackLoading) {
      debugPrint('[XtreamService] Throttling short EPG for $streamId');
      await Future.delayed(_throttleDelay);
    }

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_short_epg',
          'stream_id': streamId,
        },
        options: Options(
          extra: CacheOptions(
            store: _cacheOptions.store,
            policy: CachePolicy.request,
            maxStale: const Duration(minutes: 5), // EPG changes frequently
          ).toExtra(),
        ),
      );

      if (response.data == null || response.data['epg_listings'] == null) {
        return [];
      }

      final List<dynamic> epgData =
          response.data['epg_listings'] as List<dynamic>;
      return epgData
          .map((entry) => EpgEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // EPG is optional, don't throw on failure
      return [];
    }
  }

  /// Get short EPG as ShortEPG object (for EPGWidget)
  Future<xm.ShortEPG> getShortEPG(String streamId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    if (isPlaybackLoading) {
      debugPrint('[XtreamService] Throttling short EPG metadata for $streamId');
      await Future.delayed(_throttleDelay);
    }

    try {
      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_short_epg',
          'stream_id': streamId,
        },
        options: Options(
          extra: CacheOptions(
            store: _cacheOptions.store,
            policy: CachePolicy.request,
            maxStale: const Duration(minutes: 5),
          ).toExtra(),
        ),
      );

      if (response.data == null) {
        return const xm.ShortEPG();
      }

      return xm.ShortEPG.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      // EPG is optional, don't throw on failure
      return const xm.ShortEPG();
    }
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
