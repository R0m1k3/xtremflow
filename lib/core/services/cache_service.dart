import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cache entry with metadata
class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final int sizeEstimate;
  int accessCount;
  DateTime lastAccess;

  CacheEntry({
    required this.data,
    required this.sizeEstimate,
  })  : timestamp = DateTime.now(),
        lastAccess = DateTime.now(),
        accessCount = 0;

  bool isExpired({Duration ttl = const Duration(hours: 24)}) {
    return DateTime.now().difference(timestamp) > ttl;
  }

  void markAccess() {
    accessCount++;
    lastAccess = DateTime.now();
  }
}

/// Optimized cache service for memory management
class CacheService {
  static const _maxMemoryCacheSizeMb = 200;
  static const _maxImageCacheItems = 500;

  final Map<String, CacheEntry> _cache = {};
  int _totalSizeBytes = 0;

  /// Cache data with automatic size management
  void cache<T>(String key, T value, {int estimatedSize = 1000}) {
    // Remove old entry if exists
    if (_cache.containsKey(key)) {
      _totalSizeBytes -= _cache[key]!.sizeEstimate;
    }

    _cache[key] = CacheEntry(
      data: value,
      sizeEstimate: estimatedSize,
    );
    _totalSizeBytes += estimatedSize;

    // Trim cache if over size limit
    _trimCacheIfNeeded();
  }

  /// Get cached data
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired()) {
      entry.markAccess();
      return entry.data as T;
    }
    return null;
  }

  /// Check if key exists and is valid
  bool has(String key) {
    final entry = _cache[key];
    return entry != null && !entry.isExpired();
  }

  /// Get cache stats
  Map<String, dynamic> getStats() => {
        'totalSize': _totalSizeBytes,
        'totalSizeMb': _totalSizeBytes / (1024 * 1024),
        'itemCount': _cache.length,
        'averageSizePerItem':
            _cache.isEmpty ? 0 : _totalSizeBytes ~/ _cache.length,
      };

  /// Clear all cache
  void clear() {
    _cache.clear();
    _totalSizeBytes = 0;
  }

  /// Clear expired entries
  void clearExpired() {
    final now = DateTime.now();
    final toRemove = _cache.entries
        .where((e) => e.value.isExpired())
        .map((e) => e.key)
        .toList();

    for (final key in toRemove) {
      _totalSizeBytes -= _cache[key]!.sizeEstimate;
      _cache.remove(key);
    }
  }

  /// Trim cache by removing least recently used entries
  void _trimCacheIfNeeded() {
    const maxSize = _maxMemoryCacheSizeMb * 1024 * 1024;
    if (_totalSizeBytes > maxSize) {
      // Remove least recently accessed entries
      final sorted = _cache.entries.toList()
        ..sort((a, b) => a.value.accessCount.compareTo(b.value.accessCount));

      for (final entry in sorted) {
        if (_totalSizeBytes <= maxSize * 0.8) break;
        _totalSizeBytes -= entry.value.sizeEstimate;
        _cache.remove(entry.key);
      }
    }
  }
}

/// Cached image metadata
class CachedImage {
  final String url;
  final int sizeBytes;
  final DateTime cachedAt;
  int accessCount = 0;

  CachedImage({
    required this.url,
    required this.sizeBytes,
  }) : cachedAt = DateTime.now();
}

/// Image cache with size limiting
class ImageCacheManager {
  static const _maxImageMemoryMb = 100;
  static const _maxImages = 500;

  final Map<String, CachedImage> _imageCache = {};
  int _totalMemoryBytes = 0;

  /// Add image to cache
  void cacheImage(String url, int sizeEstimateBytes) {
    if (_imageCache.length >= _maxImages) {
      _evictLeastUsed();
    }

    _imageCache[url] = CachedImage(
      url: url,
      sizeBytes: sizeEstimateBytes,
    );
    _totalMemoryBytes += sizeEstimateBytes;

    // Trim if over size
    while (_totalMemoryBytes > _maxImageMemoryMb * 1024 * 1024) {
      _evictLeastUsed();
    }
  }

  /// Check if image is cached
  bool isCached(String url) => _imageCache.containsKey(url);

  /// Mark image as accessed
  void markAccessed(String url) {
    if (_imageCache.containsKey(url)) {
      _imageCache[url]!.accessCount++;
    }
  }

  /// Evict least used image
  void _evictLeastUsed() {
    if (_imageCache.isEmpty) return;

    final leastUsed = _imageCache.entries
        .reduce((a, b) => a.value.accessCount < b.value.accessCount ? a : b);

    _totalMemoryBytes -= leastUsed.value.sizeBytes;
    _imageCache.remove(leastUsed.key);
  }

  /// Get cache stats
  Map<String, dynamic> getStats() => {
        'totalMemoryMb': _totalMemoryBytes / (1024 * 1024),
        'cachedImages': _imageCache.length,
        'maxImages': _maxImages,
      };

  /// Clear all image cache
  void clear() {
    _imageCache.clear();
    _totalMemoryBytes = 0;
  }
}

// Riverpod providers

final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService();
});

final imageCacheManagerProvider = Provider<ImageCacheManager>((ref) {
  return ImageCacheManager();
});

/// Provider for cache statistics
final cacheStatsProvider =
    StateNotifierProvider<CacheStatsNotifier, Map<String, dynamic>>((ref) {
  final cacheService = ref.watch(cacheServiceProvider);
  return CacheStatsNotifier(cacheService);
});

class CacheStatsNotifier extends StateNotifier<Map<String, dynamic>> {
  final CacheService _cacheService;

  CacheStatsNotifier(this._cacheService) : super(_cacheService.getStats());

  void refreshStats() {
    state = _cacheService.getStats();
  }

  void clearCache() {
    _cacheService.clear();
    state = _cacheService.getStats();
  }

  void clearExpired() {
    _cacheService.clearExpired();
    state = _cacheService.getStats();
  }
}
