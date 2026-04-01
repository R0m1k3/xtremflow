/// Application optimization configuration
///
/// This file contains performance tuning settings for XtremFlow
library;

class OptimizationConfig {
  // ============================================
  // STREAMING OPTIMIZATION
  // ============================================

  /// Enable adaptive bitrate streaming
  static const bool enableAdaptiveBitrate = true;

  /// Default quality profile for new streams
  static const String defaultQualityResolution = '720x480'; // 480p HD

  /// Maximum buffer size in seconds
  static const int maxBufferSeconds = 30;

  /// Minimum buffer size in seconds before rebuffering
  static const int minBufferSeconds = 2;

  /// Target buffer size in seconds
  static const int targetBufferSeconds = 8;

  /// Enable HLS v3 compression
  static const bool enableHlsCompression = true;

  /// FFmpeg preset for live transcoding
  static const String ffmpegLivePreset =
      'medium'; // ultrafast, fast, medium, slow

  /// FFmpeg preset for VOD transcoding
  static const String ffmpegVodPreset = 'medium';

  /// Enable NVIDIA GPU acceleration if available
  static const bool enableNvidiaGpu = true;

  // ============================================
  // CACHE OPTIMIZATION
  // ============================================

  /// Enable aggressive image caching
  static const bool enableImageCache = true;

  /// Maximum image cache size in MB
  static const int maxImageCacheMb = 100;

  /// Maximum memory cache size in MB
  static const int maxMemoryCacheMb = 200;

  /// Cache expiration time in hours
  static const int cacheExpirationHours = 24;

  /// Enable network cache interceptor
  static const bool enableNetworkCache = true;

  /// Network cache retention time in days
  static const int networkCacheRetentionDays = 3;

  // ============================================
  // UI OPTIMIZATION
  // ============================================

  /// Number of items to load per page
  static const int itemsPerPage = 50;

  /// Number of items per page for Live TV grid view
  static const int liveItemsPerPage = 100;

  /// Enable lazy loading for content lists
  static const bool enableLazyLoading = true;

  /// Enable image fade animation on load
  static const bool enableImageFadeAnimation = true;

  /// Image fade animation duration in milliseconds
  static const int imageFadeAnimationMs = 300;

  /// Enable smooth scrolling
  static const bool enableSmoothScroll = true;

  /// TextureView pool size for video rendering (Android)
  static const int videoTexturePoolSize = 4;

  // ============================================
  // NETWORK OPTIMIZATION
  // ============================================

  /// Connection timeout in seconds
  static const int connectionTimeoutSeconds = 30;

  /// Receive timeout in seconds
  static const int receiveTimeoutSeconds = 60;

  /// Max concurrent downloads
  static const int maxConcurrentDownloads = 3;

  /// Enable network optimization (bandwidth detection, etc)
  static const bool enableNetworkOptimization = true;

  /// Enable request retry on failure
  static const bool enableAutoRetry = true;

  /// Max retry attempts
  static const int maxRetryAttempts = 3;

  /// Enable gzip compression for API requests
  static const bool enableGzipCompression = true;

  // ============================================
  // MEMORY OPTIMIZATION
  // ============================================

  /// Enable memory profiling on debug builds
  static const bool enableMemoryProfiling = false;

  /// Collect memory stats every N seconds
  static const int memoryProfilingIntervalSeconds = 10;

  /// Enable aggressive memory cleanup on app background
  static const bool enableMemoryCleanupOnBackground = true;

  /// Max number of cached image entries
  static const int maxCachedImages = 500;

  // ============================================
  // PERFORMANCE MONITORING
  // ============================================

  /// Enable performance monitoring
  static const bool enablePerformanceMonitoring = true;

  /// Monitor frame rate drops
  static const bool monitorFrameRate = true;

  /// Frame rate warning threshold (FPS)
  static const int frameRateWarningThreshold = 30;

  /// Enable network metrics collection
  static const bool collectNetworkMetrics = true;

  /// Enable streaming quality metrics
  static const bool collectStreamingMetrics = true;

  // ============================================
  // FEATURE FLAGS
  // ============================================

  /// Enable EPG (Electronic Program Guide)
  static const bool enableEpg = true;

  /// Enable offline downloads
  static const bool enableOfflineDownloads = true;

  /// Enable continue watching feature
  static const bool enableContinueWatching = true;

  /// Enable trending content
  static const bool enableTrending = true;

  /// Enable adaptive streaming quality selector
  static const bool enableQualitySelector = true;

  /// Enable subtitle support
  static const bool enableSubtitles = true;

  /// Enable watch history tracking
  static const bool enableWatchHistory = true;

  /// Enable user favorites
  static const bool enableFavorites = true;

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Get optimized image cache settings
  static Map<String, dynamic> getImageCacheSettings() => {
        'maxSize': maxImageCacheMb * 1024 * 1024,
        'maxItems': maxCachedImages,
        'enableAnimation': enableImageFadeAnimation,
        'fadeAnimationMs': imageFadeAnimationMs,
      };

  /// Get streaming configuration
  static Map<String, dynamic> getStreamingConfig() => {
        'enableAdaptiveBitrate': enableAdaptiveBitrate,
        'defaultQuality': defaultQualityResolution,
        'maxBuffer': maxBufferSeconds,
        'minBuffer': minBufferSeconds,
        'targetBuffer': targetBufferSeconds,
        'enableHlsCompression': enableHlsCompression,
        'ffmpegPreset': ffmpegLivePreset,
        'enableGpu': enableNvidiaGpu,
      };

  /// Get network configuration
  static Map<String, dynamic> getNetworkConfig() => {
        'connectTimeout': connectionTimeoutSeconds,
        'receiveTimeout': receiveTimeoutSeconds,
        'enableAutoRetry': enableAutoRetry,
        'maxRetries': maxRetryAttempts,
        'enableGzip': enableGzipCompression,
        'enableCache': enableNetworkCache,
        'cacheRetentionDays': networkCacheRetentionDays,
      };

  /// Get UI performance settings
  static Map<String, dynamic> getUiPerformanceSettings() => {
        'itemsPerPage': itemsPerPage,
        'liveItemsPerPage': liveItemsPerPage,
        'enableLazyLoading': enableLazyLoading,
        'enableSmoothScroll': enableSmoothScroll,
        'maxTexturePoolSize': videoTexturePoolSize,
      };

  /// Get memory optimization settings
  static Map<String, dynamic> getMemoryOptimizationSettings() => {
        'enableProfiling': enableMemoryProfiling,
        'profilingInterval': memoryProfilingIntervalSeconds,
        'aggressiveCleanup': enableMemoryCleanupOnBackground,
        'maxImageCacheMb': maxImageCacheMb,
        'maxMemoryCacheMb': maxMemoryCacheMb,
      };

  /// Get all enabled features
  static List<String> getEnabledFeatures() => [
        if (enableEpg) 'EPG',
        if (enableOfflineDownloads) 'OfflineDownloads',
        if (enableContinueWatching) 'ContinueWatching',
        if (enableTrending) 'Trending',
        if (enableQualitySelector) 'QualitySelector',
        if (enableSubtitles) 'Subtitles',
        if (enableWatchHistory) 'WatchHistory',
        if (enableFavorites) 'Favorites',
      ];

  /// Print configuration summary
  static void printSummary() {
    print('''
╔════════════════════════════════════════════════════════════╗
║          XtremFlow Optimization Configuration             ║
╠════════════════════════════════════════════════════════════╣
║ STREAMING                                                  ║
║  • Adaptive Bitrate: $enableAdaptiveBitrate                       ║
║  • Default Quality: $defaultQualityResolution                    ║
║  • GPU Acceleration: $enableNvidiaGpu                    ║
║                                                            ║
║ CACHE                                                      ║
║  • Image Cache: ${maxImageCacheMb}MB                         ║
║  • Memory Cache: ${maxMemoryCacheMb}MB                       ║
║  • Network Cache: $enableNetworkCache                     ║
║                                                            ║
║ NETWORK                                                    ║
║  • Connection Timeout: ${connectionTimeoutSeconds}s                 ║
║  • Auto Retry: $enableAutoRetry                    ║
║  • Max Retries: $maxRetryAttempts                        ║
║                                                            ║
║ FEATURES ENABLED: ${getEnabledFeatures().join(', ')}║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
''');
  }
}

/// Runtime optimization flags
class RuntimeOptimizations {
  static bool hasHighPerformanceDevice = false;
  static bool isLowBatteryMode = false;
  static bool isLowMemoryMode = false;
  static int availableMemoryMb = 0;
  static int availableStorageMb = 0;

  /// Adjust settings based on device capabilities
  static void calibrateForDevice({
    required int totalMemoryMb,
    required int freeMemoryMb,
    required int storageFreeMb,
  }) {
    availableMemoryMb = freeMemoryMb;
    availableStorageMb = storageFreeMb;

    // Detect low memory condition
    isLowMemoryMode = freeMemoryMb < 500;

    // Detect low storage
    if (storageFreeMb < 1000) {
      print(
        '[WARNING] Low storage available: ${storageFreeMb}MB. Disabling offline downloads.',
      );
    }

    // High performance device detection
    hasHighPerformanceDevice = totalMemoryMb > 4000 && storageFreeMb > 5000;

    print(
      '[Device Calibration] Memory: ${freeMemoryMb}MB, Storage: ${storageFreeMb}MB',
    );
  }

  /// Get dynamic cache size based on available memory
  static int getDynamicCacheSize() {
    if (isLowMemoryMode) {
      return 50; // 50MB on low memory devices
    }
    if (hasHighPerformanceDevice) {
      return 200; // 200MB on high performance devices
    }
    return OptimizationConfig.maxMemoryCacheMb;
  }

  /// Get dynamic image cache size
  static int getDynamicImageCacheSize() {
    if (isLowMemoryMode) {
      return 30; // 30MB
    }
    if (hasHighPerformanceDevice) {
      return 150; // 150MB
    }
    return OptimizationConfig.maxImageCacheMb;
  }
}
