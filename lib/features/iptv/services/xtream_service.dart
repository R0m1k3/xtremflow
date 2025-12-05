import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../models/xtream_models.dart';

class XtreamService {
  final PlaylistConfig config;
  late final Dio _dio;

  // Cache for reducing API calls
  final Map<String, dynamic> _cache = {};
  static const _cacheDuration = Duration(minutes: 10);
  final Map<String, DateTime> _cacheTimestamps = {};

  XtreamService(this.config) {
    _dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        queryParameters: {
          'username': config.username,
          'password': config.password,
        },
      ),
    );

    // Add caching interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Check cache before making request
          final cacheKey = options.uri.toString();
          if (_cache.containsKey(cacheKey)) {
            final timestamp = _cacheTimestamps[cacheKey];
            if (timestamp != null &&
                DateTime.now().difference(timestamp) < _cacheDuration) {
              // Return cached response
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: _cache[cacheKey],
                ),
              );
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          // Cache successful responses
          final cacheKey = response.requestOptions.uri.toString();
          _cache[cacheKey] = response.data;
          _cacheTimestamps[cacheKey] = DateTime.now();
          handler.next(response);
        },
      ),
    );
  }

  /// Authenticate and get server info
  Future<Map<String, dynamic>> authenticate() async {
    try {
      final response = await _dio.get('', queryParameters: {
        'username': config.username,
        'password': config.password,
      });
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  /// Get live streams with pagination
  Future<List<LiveChannel>> getLiveStreams({
    String? categoryId,
    int offset = 0,
    int limit = 100,
  }) async {
    try {
      final params = {
        'username': config.username,
        'password': config.password,
        'action': 'get_live_streams',
        if (categoryId != null) 'category_id': categoryId,
      };

      final response = await _dio.get('', queryParameters: params);
      final data = response.data as List;

      // Apply manual pagination (Xtream doesn't support it natively)
      final paginatedData = data.skip(offset).take(limit).toList();

      return paginatedData
          .map((json) => LiveChannel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load live streams: $e');
    }
  }

  /// Get VOD streams (movies) with pagination
  Future<List<Movie>> getMovies({
    String? categoryId,
    int offset = 0,
    int limit = 100,
  }) async {
    try {
      final params = {
        'username': config.username,
        'password': config.password,
        'action': 'get_vod_streams',
        if (categoryId != null) 'category_id': categoryId,
      };

      final response = await _dio.get('', queryParameters: params);
      final data = response.data as List;

      final paginatedData = data.skip(offset).take(limit).toList();

      return paginatedData
          .map((json) => Movie.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load movies: $e');
    }
  }

  /// Get series with pagination
  Future<List<Series>> getSeries({
    String? categoryId,
    int offset = 0,
    int limit = 100,
  }) async {
    try {
      final params = {
        'username': config.username,
        'password': config.password,
        'action': 'get_series',
        if (categoryId != null) 'category_id': categoryId,
      };

      final response = await _dio.get('', queryParameters: params);
      final data = response.data as List;

      final paginatedData = data.skip(offset).take(limit).toList();

      return paginatedData
          .map((json) => Series.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load series: $e');
    }
  }

  /// Get live categories
  Future<List<Category>> getLiveCategories() async {
    try {
      final response = await _dio.get('', queryParameters: {
        'username': config.username,
        'password': config.password,
        'action': 'get_live_categories',
      });

      final data = response.data as List;
      return data
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load categories: $e');
    }
  }

  /// Get short EPG for a specific channel
  Future<ShortEPG> getShortEPG(String channelId) async {
    try {
      final response = await _dio.get('', queryParameters: {
        'username': config.username,
        'password': config.password,
        'action': 'get_short_epg',
        'stream_id': channelId,
        'limit': '2', // Only get current and next
      });

      return ShortEPG.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      // EPG might not be available for all channels
      return const ShortEPG();
    }
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}

/// Provider for Xtream service (requires playlist config)
final xtreamServiceProvider = Provider.family<XtreamService, PlaylistConfig>(
  (ref, config) => XtreamService(config),
);
