/// INTEGRATION GUIDE - XtremFlow Optimizations
/// 
/// This guide shows how to integrate and use all the new optimization features

// ============================================
// 1. ADAPTIVE BITRATE STREAMING
// ============================================

// In your player_screen.dart, use this:
/*
import 'package:xtremflow/core/services/adaptive_bitrate_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late QualitySelector _qualitySelector;

  @override
  void initState() {
    super.initState();
    _qualitySelector = QualitySelector(
      initialQuality: QualityProfiles.hd720p,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentQuality = _qualitySelector.currentQuality;
    
    return Stack(
      children: [
        // Your video player widget
        VideoPlayer(url: _getStreamUrl(currentQuality)),
        
        // Quality indicator
        QualityIndicator(
          qualitySelector: _qualitySelector,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => QualitySelectorWidget(
                qualitySelector: _qualitySelector,
                onClose: () => Navigator.pop(context),
              ),
            );
          },
        ),
      ],
    );
  }

  String _getStreamUrl(QualityLevel quality) {
    // Return URL based on selected quality
    // Example: https://stream.example.com/video_${quality.width}x${quality.height}.m3u8
    return '';
  }
}
*/

// ============================================
// 2. SUBTITLES SUPPORT
// ============================================

// Import and use:
/*
import 'package:xtremflow/features/iptv/services/subtitle_service.dart';

// Parse SRT file
final srtContent = await rootBundle.loadString('subtitles/movie.srt');
final subtitleEntries = SubtitleService.parseSrt(srtContent);

// Get subtitle at specific time
final currentSubtitle = SubtitleService.getSubtitleAtTime(
  subtitleEntries,
  Duration(seconds: currentPosition),
);

// Download from URL
final content = await SubtitleService.downloadSubtitle(
  'https://example.com/subtitles.srt',
);
final entries = SubtitleService.parseSrt(content);

// Display in player
SubtitleOverlay(
  subtitle: currentSubtitle,
  position: Offset(0, size.height * 0.85),
)
*/

// ============================================
// 3. RECOMMEND SYSTEM (CONTINUE WATCHING, TRENDING)
// ============================================

// In your dashboard_screen.dart:
/*
import 'package:xtremflow/features/iptv/providers/recommendations_provider.dart';
import 'package:xtremflow/features/iptv/widgets/continue_watching_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final watchHistory = ref.watch(watchHistoryProvider);
    final trending = ref.watch(trendingProvider);

    return ListView(
      children: [
        // Continue Watching Section
        ContinueWatchingWidget(
          playlist: widget.playlist,
          content: widget.content,
          onItemTap: () {
            // Navigate to player
          },
        ),

        // Trending Section
        TrendingWidget(
          playlist: widget.playlist,
          content: widget.content,
          onItemTap: () {
            // Navigate to player
          },
        ),

        // Recently Added Section
        RecentlyAddedWidget(
          playlist: widget.playlist,
          content: widget.content,
          onItemTap: () {
            // Navigate to player
          },
        ),
      ],
    );
  }
}

// Track watch position:
void _onVideoProgress(Duration position, Duration duration) {
  final percentage = (position.inSeconds / duration.inSeconds) * 100;
  ref.read(watchHistoryProvider.notifier)
      .updateWatchTime(streamId, percentage);
}

// Track trending:
void _onVideoStart() {
  ref.read(trendingProvider.notifier).incrementViewCount(streamId);
}
*/

// ============================================
// 4. OFFLINE DOWNLOADS
// ============================================

// Download a video:
/*
import 'package:xtremflow/features/iptv/services/download_service.dart';

final downloadService = ref.read(downloadServiceProvider);

// Start download
final task = await downloadService.startDownload(
  id: 'movie_12345',
  title: 'Awesome Movie',
  url: 'https://stream.example.com/movie.mp4',
);

// Monitor progress
_downloadUpdateTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
  final progress = downloadService.getDownloadProgress('movie_12345');
  setState(() => _downloadProgress = progress);
});

// Pause/Resume
downloadService.pauseDownload('movie_12345');
downloadService.resumeDownload('movie_12345');

// Check if available offline
if (downloadService.isAvailableOffline('movie_12345')) {
  final filePath = downloadService.getOfflineFilePath('movie_12345');
  // Play from file path
}
*/

// ============================================
// 5. NETWORK OPTIMIZATION & PROXY
// ============================================

// Configure network with proxy:
/*
import 'package:xtremflow/core/services/network_service.dart';

final networkConfig = NetworkConfig(
  proxyUrl: 'http://proxy.example.com:8080',
  userAgent: 'CustomUser-Agent/1.0',
  customHeaders: {
    'Authorization': 'Bearer token123',
    'X-Custom-Header': 'value',
  },
  connectTimeout: Duration(seconds: 30),
  receiveTimeout: Duration(seconds: 60),
);

final networkService = OptimizedNetworkService(config: networkConfig);

// Update proxy at runtime
ref.read(networkConfigProvider.notifier)
    .setProxy('http://new-proxy:8080');
*/

// ============================================
// 6. CACHE MANAGEMENT
// ============================================

// Use cache service:
/*
import 'package:xtremflow/core/services/cache_service.dart';

final cacheService = ref.read(cacheServiceProvider);

// Cache data with automatic size management
cacheService.cache<String>('channel_list_key', jsonEncodedList, 
    estimatedSize: 50000);

// Retrieve cached data
final cachedList = cacheService.get<String>('channel_list_key');

// Check if valid
if (cacheService.has('channel_list_key')) {
  // Use cached value
}

// Get cache statistics
final stats = cacheService.getStats();
print('Cache size: ${stats['totalSizeMb']}MB');
print('Items: ${stats['itemCount']}');

// Clear expired entries
cacheService.clearExpired();

// Clear all cache
cacheService.clear();
*/

// ============================================
// 7. STREAMING METRICS & OPTIMIZATION
// ============================================

// Monitor streaming quality:
/*
import 'package:xtremflow/core/services/streaming_optimizer.dart';

final optimizer = ref.watch(streamingOptimizerProvider);

Text('Quality: ${optimizer.quality.label}'),
Text('Buffer: ${optimizer.bufferDurationMs}ms'),
Text('Rebuffers: ${optimizer.rebufferCount}'),

// Record segment download
ref.read(streamingOptimizerProvider.notifier)
    .recordSegmentDownload(bytesDownloaded, downloadDuration);

// Handle rebuffer
ref.read(streamingOptimizerProvider.notifier)
    .rebufferDetected(Duration(milliseconds: 2000));

// View metrics history
final history = ref.read(streamingOptimizerProvider.notifier)
    .getHistory();
*/

// ============================================
// 8. EPG GRID VIEW
// ============================================

// Navigate to EPG:
/*
import 'package:xtremflow/features/iptv/screens/epg_grid_screen.dart';

// In your navigation:
context.push('/epg', extra: widget.playlist);

// Or open as bottom sheet
showModalBottomSheet(
  context: context,
  builder: (context) => EpgGridScreen(playlist: widget.playlist),
);
*/

// ============================================
// 9. OPTIMIZATION CONFIG
// ============================================

// Print optimization summary:
/*
import 'package:xtremflow/core/config/optimization_config.dart';

// On app startup
OptimizationConfig.printSummary();

// Calibrate for device
RuntimeOptimizations.calibrateForDevice(
  totalMemoryMb: 8000,
  freeMemoryMb: 2000,
  storageFreeMb: 50000,
);

// Get dynamic cache sizes based on device
final cacheSizeMb = RuntimeOptimizations.getDynamicCacheSize();
final imageCacheMb = RuntimeOptimizations.getDynamicImageCacheSize();

// Check device capabilities
if (RuntimeOptimizations.hasHighPerformanceDevice) {
  // Enable all features
} else if (RuntimeOptimizations.isLowMemoryMode) {
  // Disable heavy features
}
*/

// ============================================
// 10. COMPLETE PLAYER INTEGRATION
// ============================================

// Full player screen with all optimizations:
/*
import 'package:xtremflow/core/services/adaptive_bitrate_service.dart';
import 'package:xtremflow/core/services/streaming_optimizer.dart';
import 'package:xtremflow/features/iptv/services/subtitle_service.dart';

class OptimizedPlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final int streamId;

  const OptimizedPlayerScreen({
    required this.streamUrl,
    required this.streamId,
  });

  @override
  ConsumerState<OptimizedPlayerScreen> createState() =>
      _OptimizedPlayerScreenState();
}

class _OptimizedPlayerScreenState 
    extends ConsumerState<OptimizedPlayerScreen> {
  late QualitySelector _qualitySelector;
  late VideoPlayerController _controller;
  List<SubtitleEntry> _subtitles = [];
  String? _currentSubtitle;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    // Setup quality selector
    _qualitySelector = QualitySelector(
      initialQuality: QualityProfiles.hd720p,
    );

    // Initialize video player with adaptive quality URL
    _controller = VideoPlayerController.network(
      _getQualityUrl(_qualitySelector.currentQuality),
    );

    // Load subtitles
    _loadSubtitles();

    // Start listening to playback events
    _controller.addListener(_onPlayerStateChanged);
  }

  void _loadSubtitles() async {
    // Try to auto-download subtitles
    // Example: from OpenSubtitles API
  }

  void _onPlayerStateChanged() {
    final position = _controller.value.position;
    
    // Track watch progress
    if (_controller.value.duration.inMilliseconds > 0) {
      final percentage = (position.inMilliseconds / 
          _controller.value.duration.inMilliseconds) * 100;
      ref.read(watchHistoryProvider.notifier)
          .updateWatchTime(widget.streamId, percentage);
    }

    // Update subtitle
    if (_subtitles.isNotEmpty) {
      _currentSubtitle = SubtitleService.getSubtitleAtTime(
        _subtitles,
        position,
      );
      setState(() {});
    }

    // Record streaming metrics
    final bytesEstimate = 1000; // Calculate from actual download
    ref.read(streamingOptimizerProvider.notifier)
        .recordSegmentDownload(bytesEstimate, Duration(milliseconds: 500));
  }

  String _getQualityUrl(QualityLevel quality) {
    // Return HLS master playlist or variant playlist
    return '${widget.streamUrl}/variant_${quality.width}x${quality.height}.m3u8';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(streamingOptimizerProvider);

    return Stack(
      children: [
        // Video player
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),

        // Subtitles overlay
        if (_currentSubtitle != null)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentSubtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

        // Quality indicator + metrics
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              QualityIndicator(
                qualitySelector: _qualitySelector,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => QualitySelectorWidget(
                      qualitySelector: _qualitySelector,
                      onClose: () => Navigator.pop(context),
                    ),
                  );
                },
              ),
              SizedBox(height: 8),
              BandwidthMonitor(qualitySelector: _qualitySelector),
            ],
          ),
        ),

        // Metrics display (debug)
        if (kDebugMode)
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rebuffers: ${metrics.rebufferCount}',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  Text(
                    'Buffer: ${metrics.bufferDurationMs}ms',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  Text(
                    'Quality: ${metrics.bufferDurationMs}/100',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerStateChanged);
    _controller.dispose();
    super.dispose();
  }
}
*/

// ============================================
// BEST PRACTICES
// ============================================

/*
1. ALWAYS use ref.watch() for providers in build()
   ❌ Bad: final service = ServicesService()
   ✅ Good: final service = ref.read(serviceProvider)

2. DISPOSE resources properly
   ❌ Bad: Forget to cancel timers
   ✅ Good: Override dispose() and clean up

3. HANDLE network errors gracefully
   ❌ Bad: Assume network always works
   ✅ Good: Use try-catch with retry logic

4. OPTIMIZE images
   ❌ Bad: Load full resolution images
   ✅ Good: Use cached_network_image with cache manager

5. MONITOR memory usage
   ❌ Bad: Keep unlimited cache
   ✅ Good: Use cache service with auto-eviction

6. TEST on low-end devices
   ❌ Bad: Only test on flagship phones
   ✅ Good: Test on Android 6.0 with 1GB RAM

7. MEASURE performance
   ❌ Bad: "It feels fast"
   ✅ Good: Use metrics to measure and improve
*/
