import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../models/xtream_models.dart' as xm;
import 'dart:html' as html;

/// Xtream Codes API Service
/// 
/// Handles all communication with Xtream API servers
class XtreamService {
  late final Dio _dio;
  late final CacheOptions _cacheOptions;
  
  PlaylistConfig? _currentPlaylist;

  XtreamService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    // Setup caching for API responses
    _cacheOptions = CacheOptions(
      store: HiveCacheStore('./cache'),
      policy: CachePolicy.forceCache,
      maxStale: const Duration(hours: 1),
      priority: CachePriority.high,
    );

    _dio.interceptors.add(DioCacheInterceptor(options: _cacheOptions));
  }

  /// Check if we're running on HTTPS (production)
  bool get _isHttps {
    return html.window.location.protocol == 'https:';
  }

  /// Wrap URL with proxy if needed (for HTTPS to HTTP bridge)
  String _wrapWithProxy(String url) {
    // If we're on HTTPS and the target URL is HTTP, use the proxy
    if (_isHttps && url.startsWith('http://')) {
      final baseUrl = html.window.location.origin;
      return '$baseUrl/api/xtream/$url';
    }
    return url;
  }

  /// Initialize connection with a playlist
  void setPlaylist(PlaylistConfig playlist) {
    _currentPlaylist = playlist;
  }

  /// Generate stream URL for live TV
  String getLiveStreamUrl(String streamId) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    
    final url = '${_currentPlaylist!.dns}/live/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.m3u8';
    return _wrapWithProxy(url);
  }

  /// Generate stream URL for VOD (movies)
  String getVodStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    
    final url = '${_currentPlaylist!.dns}/movie/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.$containerExtension';
    return _wrapWithProxy(url);
  }

  /// Generate stream URL for series episodes
  String getSeriesStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    
    final url = '${_currentPlaylist!.dns}/series/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.$containerExtension';
    return _wrapWithProxy(url);
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
  Future<Map<String, List<Channel>>> getLiveChannels() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // First, load categories to get the mapping
      final categoryMap = await _getLiveCategories();

      final response = await _dio.get(
        _wrapWithProxy(_currentPlaylist!.apiBaseUrl),
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_live_streams',
        },
        options: Options(extra: _cacheOptions.toExtra()),
      );

      final List<dynamic> streams = response.data as List<dynamic>;
      final Map<String, List<Channel>> groupedChannels = {};

      for (final streamData in streams) {
        final data = streamData as Map<String, dynamic>;
        // Get category name from our mapping using category_id
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        
        // Inject category_name into data before parsing
        data['category_name'] = categoryName;
        
        final channel = Channel.fromJson(data);

        if (!groupedChannels.containsKey(categoryName)) {
          groupedChannels[categoryName] = [];
        }
        groupedChannels[categoryName]!.add(channel);
      }

      return groupedChannels;
    } catch (e) {
      throw Exception('Failed to fetch live channels: $e');
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
  Future<Map<String, List<VodItem>>> getVodItems() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

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

      final List<dynamic> vods = response.data as List<dynamic>;
      final Map<String, List<VodItem>> groupedVods = {};

      for (final vodData in vods) {
        final data = vodData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        data['category_name'] = categoryName;

        final vod = VodItem.fromJson(data);

        if (!groupedVods.containsKey(categoryName)) {
          groupedVods[categoryName] = [];
        }
        groupedVods[categoryName]!.add(vod);
      }

      return groupedVods;
    } catch (e) {
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
  Future<Map<String, List<Series>>> getSeries() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

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

      final List<dynamic> seriesList = response.data as List<dynamic>;
      final Map<String, List<Series>> groupedSeries = {};

      for (final seriesData in seriesList) {
        final data = seriesData as Map<String, dynamic>;
        final categoryId = data['category_id']?.toString() ?? '';
        final categoryName = categoryMap[categoryId] ?? 'Uncategorized';
        data['category_name'] = categoryName;

        final series = Series.fromJson(data);

        if (!groupedSeries.containsKey(categoryName)) {
          groupedSeries[categoryName] = [];
        }
        groupedSeries[categoryName]!.add(series);
      }

      return groupedSeries;
    } catch (e) {
      throw Exception('Failed to fetch series: $e');
    }
  }

  /// Get movies with pagination support
  Future<List<xm.Movie>> getMovies({int offset = 0, int limit = 100}) async {
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
      final endIndex = (offset + limit) > allMovies.length ? allMovies.length : offset + limit;
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

  /// Get series with pagination support (returns flat list)
  Future<List<xm.Series>> getSeriesPaginated({int offset = 0, int limit = 100}) async {
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
      final endIndex = (offset + limit) > allSeries.length ? allSeries.length : offset + limit;
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

  /// Get short EPG for a specific stream
  /// 
  /// Returns "Now" and "Next" program info
  Future<List<EpgEntry>> getShortEpg(String streamId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

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

      final List<dynamic> epgData = response.data['epg_listings'] as List<dynamic>;
      return epgData
          .map((entry) => EpgEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // EPG is optional, don't throw on failure
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
