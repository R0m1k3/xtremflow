import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/adaptive_bitrate_service.dart';

/// Video streaming performance metrics
class StreamingMetrics {
  final double averageNetworkBitrate;
  final double currentNetworkBitrate;
  final int bufferDurationMs;
  final int segmentDownloadTimeMs;
  final int rebufferCount;
  final DateTime startTime;
  final DateTime? endTime;

  StreamingMetrics({
    required this.averageNetworkBitrate,
    required this.currentNetworkBitrate,
    required this.bufferDurationMs,
    required this.segmentDownloadTimeMs,
    required this.rebufferCount,
    required this.startTime,
    this.endTime,
  });

  double get totalPlaybackSeconds =>
      (endTime ?? DateTime.now()).difference(startTime).inSeconds.toDouble();

  double get qualityScore {
    // Score based on metrics
    var score = 100.0;

    // Penalize for rebuffering
    score -= rebufferCount * 10;

    // Penalize for low bitrate
    if (currentNetworkBitrate < 1000000) score -= 20;
    if (currentNetworkBitrate < 500000) score -= 30;

    // Reward for smooth playback
    if (rebufferCount == 0) score += 10;

    return (score).clamp(0, 100);
  }

  @override
  String toString() => '''
StreamingMetrics:
  - Avg Bitrate: ${(averageNetworkBitrate / 1000000).toStringAsFixed(2)} Mbps
  - Current Bitrate: ${(currentNetworkBitrate / 1000000).toStringAsFixed(2)} Mbps
  - Buffer: ${bufferDurationMs}ms
  - Segment DL Time: ${segmentDownloadTimeMs}ms
  - Rebuffers: $rebufferCount
  - Quality Score: ${qualityScore.toStringAsFixed(1)}
  - Duration: $totalPlaybackSeconds seconds
''';
}

/// Advanced streaming optimizer
class StreamingOptimizer {
  final QualitySelector qualitySelector;
  final _metrics = <StreamingMetrics>[];
  late StreamingMetrics _currentMetrics;
  final StreamController<StreamingMetrics> _metricsController =
      StreamController.broadcast();
  late Timer _metricsTimer;

  final int _segmentStartTime = 0;
  int _totalBytesDownloaded = 0;
  int _rebufferCount = 0;
  int _lastBufferNotificationTime = 0;

  StreamingOptimizer({required this.qualitySelector}) {
    _initializeMetrics();
    _startMetricsCollection();
  }

  void _initializeMetrics() {
    _currentMetrics = StreamingMetrics(
      averageNetworkBitrate: 0,
      currentNetworkBitrate: 0,
      bufferDurationMs: 0,
      segmentDownloadTimeMs: 0,
      rebufferCount: 0,
      startTime: DateTime.now(),
    );
  }

  void _startMetricsCollection() {
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateMetrics();
    });
  }

  void _updateMetrics() {
    final bandwidthBps = qualitySelector.getEstimatedBandwidthMbps() * 1000000;
    _currentMetrics = StreamingMetrics(
      averageNetworkBitrate: _totalBytesDownloaded > 0
          ? (_totalBytesDownloaded * 8 / _currentMetrics.totalPlaybackSeconds)
          : 0,
      currentNetworkBitrate: bandwidthBps,
      bufferDurationMs: _currentMetrics.bufferDurationMs,
      segmentDownloadTimeMs: _currentMetrics.segmentDownloadTimeMs,
      rebufferCount: _rebufferCount,
      startTime: _currentMetrics.startTime,
    );

    _metrics.add(_currentMetrics);
    _metricsController.add(_currentMetrics);
  }

  /// Record segment download
  void recordSegmentDownload(int bytes, Duration downloadTime) {
    _totalBytesDownloaded += bytes;
    final downloadMs = downloadTime.inMilliseconds;

    _currentMetrics = _currentMetrics;
    qualitySelector.recordBandwidth(bytes);
  }

  /// Handle rebuffer event
  void rebufferDetected(Duration duration) {
    _rebufferCount++;
    _lastBufferNotificationTime = DateTime.now().millisecondsSinceEpoch;

    _currentMetrics = StreamingMetrics(
      averageNetworkBitrate: _currentMetrics.averageNetworkBitrate,
      currentNetworkBitrate: _currentMetrics.currentNetworkBitrate,
      bufferDurationMs: duration.inMilliseconds,
      segmentDownloadTimeMs: _currentMetrics.segmentDownloadTimeMs,
      rebufferCount: _rebufferCount,
      startTime: _currentMetrics.startTime,
    );

    // Auto downgrade quality on rebuffer
    qualitySelector.rebufferDetected();
  }

  /// Get current streaming metrics
  StreamingMetrics getMetrics() => _currentMetrics;

  /// Get metrics stream for real-time monitoring
  Stream<StreamingMetrics> get metricsStream => _metricsController.stream;

  /// Get metrics history
  List<StreamingMetrics> getMetricsHistory() => List.from(_metrics);

  /// Finalize streaming session
  void finalize() {
    _currentMetrics = StreamingMetrics(
      averageNetworkBitrate: _currentMetrics.averageNetworkBitrate,
      currentNetworkBitrate: _currentMetrics.currentNetworkBitrate,
      bufferDurationMs: _currentMetrics.bufferDurationMs,
      segmentDownloadTimeMs: _currentMetrics.segmentDownloadTimeMs,
      rebufferCount: _rebufferCount,
      startTime: _currentMetrics.startTime,
      endTime: DateTime.now(),
    );
  }

  /// Clean up resources
  void dispose() {
    _metricsTimer.cancel();
    _metricsController.close();
  }
}

/// Buffer size calculator for adaptive streaming
class BufferCalculator {
  static const _minBufferMs = 1000; // 1 second
  static const _targetBufferMs = 8000; // 8 seconds
  static const _maxBufferMs = 30000; // 30 seconds

  /// Calculate optimal buffer size based on bandwidth
  static int calculateOptimalBuffer(
    int estimatedBandwidthBps,
    int bitrateOfCurrentQuality,
  ) {
    // Rule: buffer should be able to hold 8 seconds worth of content
    final neededBytes = (bitrateOfCurrentQuality * _targetBufferMs) ~/ 8000;
    final availableBytes = (estimatedBandwidthBps * _targetBufferMs) ~/ 8000;

    // If we can't sustain the bitrate + have buffer, reduce target
    if (availableBytes < neededBytes) {
      return _minBufferMs;
    }

    // Normal case
    return _targetBufferMs;
  }

  /// Calculate recommended segment duration
  static Duration calculateSegmentDuration(int estimatedBandwidthBps) {
    if (estimatedBandwidthBps < 500000) {
      // Very low bandwidth: shorter segments
      return const Duration(seconds: 2);
    } else if (estimatedBandwidthBps < 2000000) {
      // Low bandwidth
      return const Duration(seconds: 4);
    } else {
      // Good bandwidth
      return const Duration(seconds: 6);
    }
  }

  /// Calculate maximum playback quality
  static QualityLevel selectQualityForBandwidth(
    int estimatedBandwidthBps,
  ) {
    final availableProfiles = QualityProfiles.getBalancedProfiles();
    return BandwidthDetector.selectBestQuality(
      estimatedBandwidthBps,
      availableProfiles,
    );
  }
}

// Riverpod providers

final streamingOptimizerProvider =
    StateNotifierProvider<StreamingOptimizerNotifier, StreamingMetrics>((ref) {
  final qualitySelector = ref.watch(qualitySelectorProvider);
  return StreamingOptimizerNotifier(qualitySelector);
});

final qualitySelectorProvider = Provider<QualitySelector>((ref) {
  return QualitySelector(initialQuality: QualityProfiles.hd720p);
});

class StreamingOptimizerNotifier extends StateNotifier<StreamingMetrics> {
  final QualitySelector _qualitySelector;
  late StreamingOptimizer _optimizer;

  StreamingOptimizerNotifier(this._qualitySelector)
      : super(
          StreamingMetrics(
            averageNetworkBitrate: 0,
            currentNetworkBitrate: 0,
            bufferDurationMs: 0,
            segmentDownloadTimeMs: 0,
            rebufferCount: 0,
            startTime: DateTime.now(),
          ),
        ) {
    _optimizer = StreamingOptimizer(qualitySelector: _qualitySelector);

    // Listen to metrics updates
    _optimizer.metricsStream.listen((metrics) {
      state = metrics;
    });
  }

  void recordSegmentDownload(int bytes, Duration duration) {
    _optimizer.recordSegmentDownload(bytes, duration);
  }

  void rebufferDetected(Duration duration) {
    _optimizer.rebufferDetected(duration);
  }

  List<StreamingMetrics> getHistory() => _optimizer.getMetricsHistory();

  @override
  void dispose() {
    _optimizer.dispose();
    super.dispose();
  }
}
