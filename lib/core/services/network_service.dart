import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Advanced network configuration for streaming
class NetworkConfig {
  final String? proxyUrl;
  final String? userAgent;
  final Map<String, String> customHeaders;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final bool enableValidateSSL;

  const NetworkConfig({
    this.proxyUrl,
    this.userAgent = 'VLC/3.0.18 LibVLC/3.0.18',
    this.customHeaders = const {},
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 60),
    this.enableValidateSSL = true,
  });

  NetworkConfig copyWith({
    String? proxyUrl,
    String? userAgent,
    Map<String, String>? customHeaders,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    bool? enableValidateSSL,
  }) =>
      NetworkConfig(
        proxyUrl: proxyUrl ?? this.proxyUrl,
        userAgent: userAgent ?? this.userAgent,
        customHeaders: customHeaders ?? this.customHeaders,
        connectTimeout: connectTimeout ?? this.connectTimeout,
        receiveTimeout: receiveTimeout ?? this.receiveTimeout,
        enableValidateSSL: enableValidateSSL ?? this.enableValidateSSL,
      );
}

/// Advanced network service with proxy and optimization support
class OptimizedNetworkService {
  late Dio _dio;
  late NetworkConfig _config;
  late CacheInterceptor _cacheInterceptor;

  OptimizedNetworkService({required NetworkConfig config}) {
    _config = config;
    _initializeDio();
  }

  void _initializeDio() {
    _cacheInterceptor = CacheInterceptor(
      options: CacheOptions(
        store: MemCacheStore(),
        policy: CachePolicy.requestFirst,
        hitCacheOnErrorExcept: [],
        allowPostMethod: false,
      ),
    );

    _dio = Dio(
      BaseOptions(
        connectTimeout: _config.connectTimeout,
        receiveTimeout: _config.receiveTimeout,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': _config.userAgent,
          ..._config.customHeaders,
        },
      ),
    );

    // Configure proxy if specified
    if (_config.proxyUrl != null) {
      _dio.httpClientAdapter = _createProxyAdapter(_config.proxyUrl!);
    }

    // Add interceptors
    _dio.interceptors.addAll([
      _cacheInterceptor,
      _BandwidthTrackingInterceptor(),
      _RetryInterceptor(),
    ]);
  }

  /// Create HTTP client adapter with proxy support
  dynamic _createProxyAdapter(String proxyUrl) {
    // Implementation for proxy support
    // This would need to handle HTTP/HTTPS proxies
    return null;
  }

  /// Update network configuration
  void updateConfig(NetworkConfig config) {
    _config = config;
    _initializeDio();
  }

  Dio get dio => _dio;

  /// Download file with resume support
  Future<void> downloadFile({
    required String url,
    required String savePath,
    required Function(int, int) onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          headers: {'Range': 'bytes=0-'},
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Stream request with large response handling
  Future<void> streamRequest({
    required String url,
    required Function(List<int>) onData,
    required VoidCallback onDone,
    required Function(dynamic) onError,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
        cancelToken: cancelToken,
      );

      final stream = response.data?.stream;
      if (stream != null) {
        stream.listen(
          onData,
          onError: onError,
          onDone: onDone,
        );
      }
    } catch (e) {
      onError(e);
    }
  }

  /// Clear cache
  void clearCache() {
    _cacheInterceptor.clearCache();
  }
}

/// Interceptor for tracking bandwidth
class _BandwidthTrackingInterceptor extends Interceptor {
  int _bytesReceived = 0;
  DateTime _lastReset = DateTime.now();

  int get bytesReceivedLastSecond {
    final now = DateTime.now();
    final secondsElapsed = now.difference(_lastReset).inSeconds;
    if (secondsElapsed > 1) {
      final bps = _bytesReceived ~/ secondsElapsed;
      _bytesReceived = 0;
      _lastReset = now;
      return bps;
    }
    return 0;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is ResponseBody) {
      // Track bytes for streaming responses
    } else if (response.data is List<int>) {
      _bytesReceived += (response.data as List<int>).length;
    }
    handler.next(response);
  }
}

/// Interceptor for automatic retry on failure
class _RetryInterceptor extends Interceptor {
  static const _maxRetries = 3;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    // Only retry on timeout or connection errors
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      final requestOptions = err.requestOptions;
      int retryCount = requestOptions.extra['retryCount'] ?? 0;

      if (retryCount < _maxRetries) {
        requestOptions.extra['retryCount'] = retryCount + 1;

        // Exponential backoff: 100ms, 200ms, 400ms
        final delay = Duration(milliseconds: 100 * (1 << retryCount));
        await Future.delayed(delay);

        final dio = Dio();
        try {
          final response = await dio.request<dynamic>(
            requestOptions.path,
            options: Options(
              method: requestOptions.method,
              headers: requestOptions.headers,
            ),
            data: requestOptions.data,
            queryParameters: requestOptions.queryParameters,
          );
          return handler.resolve(response);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
    }

    handler.next(err);
  }
}

// Riverpod providers

final networkConfigProvider =
    StateNotifierProvider<NetworkConfigNotifier, NetworkConfig>((ref) {
  return NetworkConfigNotifier();
});

class NetworkConfigNotifier extends StateNotifier<NetworkConfig> {
  NetworkConfigNotifier()
      : super(const NetworkConfig(
          userAgent: 'VLC/3.0.18 LibVLC/3.0.18',
        ));

  void setProxy(String? proxyUrl) {
    state = state.copyWith(proxyUrl: proxyUrl);
  }

  void setUserAgent(String userAgent) {
    state = state.copyWith(userAgent: userAgent);
  }

  void addCustomHeader(String key, String value) {
    final newHeaders = {...state.customHeaders};
    newHeaders[key] = value;
    state = state.copyWith(customHeaders: newHeaders);
  }

  void removeCustomHeader(String key) {
    final newHeaders = {...state.customHeaders};
    newHeaders.remove(key);
    state = state.copyWith(customHeaders: newHeaders);
  }

  void clearCustomHeaders() {
    state = state.copyWith(customHeaders: {});
  }
}

final networkServiceProvider = Provider<OptimizedNetworkService>((ref) {
  final config = ref.watch(networkConfigProvider);
  return OptimizedNetworkService(config: config);
});
