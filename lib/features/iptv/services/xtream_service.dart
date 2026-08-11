import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../models/xtream_models.dart' as xm;

/// Limiteur de concurrence minimal (pas de dépendance supplémentaire).
class _Semaphore {
  _Semaphore(this.max);

  final int max;
  int _current = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_current < max) {
      _current++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}

/// Xtream Codes API Service
///
/// Handles all communication with Xtream API servers
class XtreamService {
  /// Une grille de chaînes déclenche un appel EPG par tuile visible — une
  /// trentaine de requêtes simultanées vers `player_api.php`. Beaucoup de
  /// panneaux Xtream limitent le débit et répondent en erreur au-delà de
  /// quelques connexions parallèles, ce qui vide l'EPG de toute la grille.
  /// On sérialise donc par petits paquets.
  static final _Semaphore _epgGate = _Semaphore(3);

  /// Action EPG retenue pour ce panneau.
  ///
  /// `get_short_epg` est la requête légère (2-3 programmes) mais une partie
  /// des panneaux répond `{"epg_listings":[]}` en permanence ; seule
  /// `get_simple_data_table` y renvoie le guide. On teste la première, et
  /// dès qu'un panneau se révèle incapable de la servir on bascule
  /// définitivement, pour ne pas payer deux requêtes par tuile de grille.
  static const _epgActionShort = 'get_short_epg';
  static const _epgActionTable = 'get_simple_data_table';
  static String _epgAction = _epgActionShort;

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

    // Attach the backend session token: the Xtream gateway
    // (/api/xtream-api) requires authentication and injects the IPTV
    // credentials server-side.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (kIsWeb) {
            final token = html.window.localStorage['auth_token'];
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
  }

  /// GET on the authenticated Xtream gateway. Credentials are injected by
  /// the backend; the client only passes the action and its parameters.
  Future<Response<dynamic>> _apiGet(
    Map<String, String> params, {
    Options? options,
  }) {
    return _dio.get(
      '$_backendBaseUrl/api/xtream-api',
      queryParameters: params,
      options: options ?? Options(extra: _cacheOptions.toExtra()),
    );
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

  /// Initialize connection with a playlist
  void setPlaylist(PlaylistConfig playlist) {
    _currentPlaylist = playlist;
  }

  /// Generate stream URL for live TV (HLS)
  /// [quality]: source | high | medium | low (server-side FFmpeg preset)
  String getLiveStreamUrl(String streamId, {String quality = 'high'}) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/live/$streamId/$quality/playlist.m3u8';
  }

  /// Generate stream URL for live TV (Direct MPEG-TS)
  /// Faster zapping on compatible players (mpegts.js)
  String getLiveStreamUrlTs(String streamId) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    // Backend route injects the Xtream credentials server-side
    return '$_backendBaseUrl/api/live/$streamId.ts';
  }

  /// Generate stream URL for VOD (movies)
  /// [quality]: source | high | medium | low (server-side FFmpeg preset)
  String getVodStreamUrl(
    String streamId,
    String containerExtension, {
    String quality = 'high',
  }) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/vod/$streamId/$quality/playlist.m3u8';
  }

  /// Generate stream URL for series episodes
  String getSeriesStreamUrl(
    String streamId,
    String containerExtension, {
    String quality = 'high',
  }) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    return '$_backendBaseUrl/api/vod/$streamId/$quality/playlist.m3u8?type=series';
  }

  /// Authenticate and get server info
  Future<Map<String, dynamic>> authenticate() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _apiGet({});

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  /// Load categories mapping (category_id -> category_name)
  Future<Map<String, String>> _getLiveCategories() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _apiGet({'action': 'get_live_categories'});

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
  Future<Map<String, List<Channel>>> getLiveChannels({
    bool refresh = false,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    final options = refresh
        ? _cacheOptions
            .copyWith(policy: CachePolicy.refreshForceCache)
            .toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize categories and streams fetching
      final results = await Future.wait([
        _getLiveCategories(),
        _apiGet(
          {'action': 'get_live_streams'},
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
      final cached =
          _loadFromLocalCache<Channel>('live_channels', Channel.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch live channels: $e');
    }
  }

  void _saveToLocalCache(String key, Map<String, dynamic> data) {
    if (!kIsWeb) return;
    try {
      final jsonStr = jsonEncode(data);
      html.window.localStorage['xtream_cache_${_currentPlaylist?.id}_$key'] =
          jsonStr;
    } catch (e) {
      debugPrint('Error saving to local cache ($key): $e');
    }
  }

  Map<String, List<T>> _loadFromLocalCache<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (!kIsWeb) return {};
    try {
      final jsonStr =
          html.window.localStorage['xtream_cache_${_currentPlaylist?.id}_$key'];
      if (jsonStr == null) return {};

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final result = <String, List<T>>{};

      data.forEach((cat, items) {
        if (items is List) {
          result[cat] =
              items.map((i) => fromJson(i as Map<String, dynamic>)).toList();
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
      final response = await _apiGet({'action': 'get_vod_categories'});

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
        ? _cacheOptions
            .copyWith(policy: CachePolicy.refreshForceCache)
            .toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize VOD categories and streams fetching
      final results = await Future.wait([
        _getVodCategories(),
        _apiGet(
          {'action': 'get_vod_streams'},
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
      final cached =
          _loadFromLocalCache<VodItem>('vod_items', VodItem.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch VOD items: $e');
    }
  }

  /// Load Series categories mapping
  Future<Map<String, String>> _getSeriesCategories() async {
    if (_currentPlaylist == null) return {};

    try {
      final response = await _apiGet({'action': 'get_series_categories'});

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
        ? _cacheOptions
            .copyWith(policy: CachePolicy.refreshForceCache)
            .toExtra()
        : _cacheOptions.toExtra();

    try {
      // Parallelize Series categories and streams fetching
      final results = await Future.wait([
        _getSeriesCategories(),
        _apiGet(
          {'action': 'get_series'},
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
      final cached =
          _loadFromLocalCache<Series>('series_items', Series.fromJson);
      if (cached.isNotEmpty) return cached;
      throw Exception('Failed to fetch series: $e');
    }
  }

  /// Get movies with pagination support
  Future<List<xm.Movie>> getMoviesPaginated({
    int offset = 0,
    int limit = 100,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load categories for mapping
      final categoryMap = await _getVodCategories();

      final response = await _apiGet({'action': 'get_vod_streams'});

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

      final response = await _apiGet({'action': 'get_vod_streams'});

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
  Future<List<xm.Series>> getSeriesPaginated({
    int offset = 0,
    int limit = 100,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load categories for mapping
      final categoryMap = await _getSeriesCategories();

      final response = await _apiGet({'action': 'get_series'});

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

      final response = await _apiGet({'action': 'get_series'});

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
      final response = await _apiGet({
        'action': 'get_series_info',
        'series_id': seriesId,
      });

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
      final response = await _apiGet({
        'action': 'get_vod_info',
        'vod_id': vodId,
      });

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
    final listings = await _fetchEpgListings(streamId);
    return listings.map(EpgEntry.fromJson).toList();
  }

  /// Get short EPG as ShortEPG object (for EPGWidget)
  Future<xm.ShortEPG> getShortEPG(String streamId) async {
    final listings = await _fetchEpgListings(streamId);
    if (listings.isEmpty) return const xm.ShortEPG();
    return xm.ShortEPG.fromJson({'epg_listings': listings});
  }

  /// Récupère le guide d'une chaîne, normalisé et réduit à la fenêtre utile.
  ///
  /// Bascule automatiquement de `get_short_epg` vers `get_simple_data_table`
  /// quand le panneau ne sert pas la première : voir [_epgAction].
  Future<List<Map<String, dynamic>>> _fetchEpgListings(String streamId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    if (isPlaybackLoading) {
      debugPrint('[XtreamService] Throttling short EPG for $streamId');
      await Future.delayed(_throttleDelay);
    }

    await _epgGate.acquire();
    try {
      var listings = await _requestEpg(streamId, _epgAction);

      // Panneau muet sur l'action légère : on retente avec le tableau complet
      // et on mémorise le choix pour toutes les chaînes suivantes.
      if (listings.isEmpty && _epgAction == _epgActionShort) {
        listings = await _requestEpg(streamId, _epgActionTable);
        if (listings.isNotEmpty) {
          debugPrint(
            '[XtreamService] EPG : $_epgActionShort vide sur ce panneau, '
            'bascule définitive vers $_epgActionTable',
          );
          _epgAction = _epgActionTable;
        }
      }

      return _normalizeListings(listings);
    } finally {
      _epgGate.release();
    }
  }

  Future<List<dynamic>> _requestEpg(String streamId, String action) async {
    try {
      final response = await _apiGet(
        {
          'action': action,
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

      var data = response.data;

      // Certains panneaux renvoient du JSON avec un Content-Type textuel :
      // Dio livre alors une String brute et l'accès par clé échouait
      // silencieusement, aboutissant au même « No Info » qu'une vraie panne.
      if (data is String) {
        if (data.trim().isEmpty) {
          debugPrint('[XtreamService] EPG $streamId : réponse vide');
          return const [];
        }
        try {
          data = json.decode(data);
        } catch (_) {
          debugPrint(
            '[XtreamService] EPG $streamId : réponse non-JSON '
            '(${response.headers.value('content-type')}) — '
            '${data.length > 120 ? '${data.substring(0, 120)}…' : data}',
          );
          return const [];
        }
      }

      if (data == null) {
        debugPrint('[XtreamService] EPG $streamId : corps nul');
        return const [];
      }

      if (data is! Map || data['epg_listings'] is! List) {
        // Cas typique de `get_epg` / `get_short_epg` non supportés : le
        // panneau répond 200 avec le payload d'authentification.
        debugPrint(
          '[XtreamService] EPG $streamId ($action) : pas de champ '
          'epg_listings (clés: '
          '${data is Map ? data.keys.toList() : data.runtimeType})',
        );
        return const [];
      }

      return data['epg_listings'] as List<dynamic>;
    } on DioException catch (e) {
      // L'EPG reste optionnel — mais avaler l'erreur en silence rendait toute
      // panne indiscernable d'une grille réellement vide.
      debugPrint(
        '[XtreamService] EPG $streamId ($action) en échec : '
        'HTTP ${e.response?.statusCode} ${e.type} — ${e.message}',
      );
      return const [];
    } catch (e) {
      debugPrint('[XtreamService] EPG $streamId ($action) en échec : $e');
      return const [];
    }
  }

  /// Aligne les dates sur de l'ISO-8601 UTC et ne garde que la fenêtre utile.
  ///
  /// Deux raisons :
  /// * `get_simple_data_table` renvoie plusieurs jours de programmes (~35 Ko
  ///   par chaîne). Les appelants prennent « le premier élément » comme
  ///   programme courant : sans coupe, ils afficheraient un programme
  ///   d'avant-hier.
  /// * Les champs texte `start`/`end` sont dans le fuseau du panneau et sans
  ///   indicateur de zone ; seuls les `*_timestamp` (epoch UTC) sont fiables.
  static List<Map<String, dynamic>> _normalizeListings(List<dynamic> raw) {
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (final item in raw) {
      if (item is! Map) continue;
      final entry = Map<String, dynamic>.from(item);

      final start = _epgDate(entry['start_timestamp'], entry['start']);
      final end = _epgDate(
        entry['stop_timestamp'] ?? entry['end_timestamp'],
        entry['stop'] ?? entry['end'],
      );
      if (start == null || end == null) continue;

      // Programme déjà terminé : sans intérêt pour un « en cours / à suivre ».
      if (end.isBefore(now)) continue;

      entry['start'] = start.toIso8601String();
      entry['end'] = end.toIso8601String();
      entry['stop'] = entry['end'];
      result.add(entry);

      if (result.length >= 8) break;
    }

    return result;
  }

  /// Epoch UTC prioritaire, repli sur la chaîne « YYYY-MM-DD HH:MM:SS ».
  static DateTime? _epgDate(dynamic timestamp, dynamic text) {
    final seconds = timestamp is int ? timestamp : int.tryParse('$timestamp');
    if (seconds != null && seconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    }
    final str = text?.toString() ?? '';
    if (str.isEmpty) return null;
    return DateTime.tryParse(
      str.contains(' ') && !str.contains('T') ? str.replaceFirst(' ', 'T') : str,
    );
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
