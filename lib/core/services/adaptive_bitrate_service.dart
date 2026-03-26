/// Adaptive Bitrate (ABR) Streaming Handler for HLS
/// 
/// Supports multi-bitrate HLS playlists for adaptive streaming
/// with fallback options for poor network conditions

import 'dart:async';
import 'dart:io';

/// Represents a video quality level for adaptive bitrate streaming
class QualityLevel {
  final String resolution;
  final int bitrateBps;
  final int width;
  final int height;
  final String ffmpegPreset; // ultrafast, fast, medium, slow
  final String label;

  const QualityLevel({
    required this.resolution,
    required this.bitrateBps,
    required this.width,
    required this.height,
    this.ffmpegPreset = 'medium',
    required this.label,
  });

  /// Get FFmpeg video bitrate argument
  String get videoBitrateArg => '${(bitrateBps * 0.75).toInt() ~/ 1000}k';

  /// Get FFmpeg maxrate argument (150% of bitrate)
  String get maxRateArg => '${((bitrateBps * 1.5).toInt() ~/ 1000)}k';

  /// Get FFmpeg buffer size argument
  String get bufferSizeArg => '${((bitrateBps * 2).toInt() ~/ 1000)}k';

  @override
  String toString() => '$label ($resolution - ${bitrateBps ~/ 1000000}Mbps)';
}

/// Standard quality profiles for adaptive streaming
class QualityProfiles {
  // Mobile & Low Bandwidth
  static const mobile240p = QualityLevel(
    resolution: '426x240',
    bitrateBps: 500000, // 0.5 Mbps
    width: 426,
    height: 240,
    ffmpegPreset: 'ultrafast',
    label: '240p (Low)',
  );

  static const mobile360p = QualityLevel(
    resolution: '640x360',
    bitrateBps: 1200000, // 1.2 Mbps
    width: 640,
    height: 360,
    ffmpegPreset: 'ultrafast',
    label: '360p (Mobile)',
  );

  // Standard Quality
  static const hd480p = QualityLevel(
    resolution: '854x480',
    bitrateBps: 2500000, // 2.5 Mbps
    width: 854,
    height: 480,
    ffmpegPreset: 'fast',
    label: '480p (SD)',
  );

  static const hd720p = QualityLevel(
    resolution: '1280x720',
    bitrateBps: 5000000, // 5 Mbps
    width: 1280,
    height: 720,
    ffmpegPreset: 'medium',
    label: '720p (HD)',
  );

  // High Quality
  static const fhd1080p = QualityLevel(
    resolution: '1920x1080',
    bitrateBps: 8000000, // 8 Mbps
    width: 1920,
    height: 1080,
    ffmpegPreset: 'medium',
    label: '1080p (Full HD)',
  );

  // Ultra HD
  static const uhd2k = QualityLevel(
    resolution: '2560x1440',
    bitrateBps: 15000000, // 15 Mbps
    width: 2560,
    height: 1440,
    ffmpegPreset: 'slow',
    label: '2K (QHD)',
  );

  static const uhd4k = QualityLevel(
    resolution: '3840x2160',
    bitrateBps: 25000000, // 25 Mbps
    width: 3840,
    height: 2160,
    ffmpegPreset: 'slow',
    label: '4K',
  );

  /// Get default profiles for balanced streaming
  static List<QualityLevel> getBalancedProfiles() => [
    mobile240p,
    mobile360p,
    hd480p,
    hd720p,
    fhd1080p,
  ];

  /// Get all available profiles
  static List<QualityLevel> getAllProfiles() => [
    mobile240p,
    mobile360p,
    hd480p,
    hd720p,
    fhd1080p,
    uhd2k,
    uhd4k,
  ];

  /// Get profiles suitable for streaming type
  static List<QualityLevel> getProfiles({
    required String type, // 'live', 'vod', 'low-bandwidth'
    int? maxBitrateBps,
  }) {
    List<QualityLevel> profiles = getBalancedProfiles();

    // Filter by streaming type
    if (type == 'live') {
      // Live TV prefers lower bitrates for stability
      profiles = [mobile240p, mobile360p, hd480p, hd720p];
    } else if (type == 'low-bandwidth') {
      // Mobile/low bandwidth - only lower profiles
      profiles = [mobile240p, mobile360p, hd480p];
    }

    // Filter by max bitrate if specified
    if (maxBitrateBps != null) {
      profiles = profiles.where((p) => p.bitrateBps <= maxBitrateBps).toList();
    }

    // Ensure at least one profile
    if (profiles.isEmpty) {
      profiles = [mobile240p];
    }

    return profiles;
  }
}

/// Bandwidth detector for adaptive bitrate selection
class BandwidthDetector {
  final _samples = <DateTime, int>{}; // timestamp -> bytes downloaded
  int _totalBytesLastPeriod = 0;
  Duration _sampleWindow = const Duration(seconds: 10);

  /// Record bytes downloaded at current time
  void recordBytes(int bytes) {
    final now = DateTime.now();
    _samples[now] = bytes;

    // Clean up old samples
    final cutoff = now.subtract(_sampleWindow);
    _samples.removeWhere((time, _) => time.isBefore(cutoff));
  }

  /// Estimate current bandwidth in bps
  int estimateBandwidthBps() {
    if (_samples.isEmpty) return 0;

    int totalBytes = 0;
    _samples.values.forEach((bytes) => totalBytes += bytes);

    final timeSpan = DateTime.now()
        .difference(
          _samples.keys.reduce((a, b) => a.isBefore(b) ? a : b),
        )
        .inMilliseconds;

    if (timeSpan == 0) return 0;

    // bytes per second * 8 = bits per second
    return ((totalBytes / (timeSpan / 1000)) * 8).toInt();
  }

  /// Get estimated bandwidth in Mbps
  double estimateBandwidthMbps() {
    return estimateBandwidthBps() / 1000000;
  }

  /// Select best quality level based on bandwidth
  static QualityLevel selectBestQuality(
    int bandwidthBps,
    List<QualityLevel> availableProfiles,
  ) {
    // Use 75% of detected bandwidth for conservative selection
    final targetBitrate = (bandwidthBps * 0.75).toInt();

    // Find highest quality that fits our bandwidth
    var best = availableProfiles[0];
    for (final profile in availableProfiles) {
      if (profile.bitrateBps <= targetBitrate) {
        best = profile;
      } else {
        break;
      }
    }

    return best;
  }
}

/// Master playlist generator for HLS variant streams
class HlsMasterPlaylistGenerator {
  /// Generate M3U8 master playlist with multiple quality variants
  static String generateMasterPlaylist({
    required List<QualityLevel> qualityLevels,
    required String baseUrl,
    bool includeSubtitles = false,
  }) {
    final buffer = StringBuffer();

    // HLS version 3 for compatibility
    buffer.writeln('#EXTM3U');
    buffer.writeln('#EXT-X-VERSION:3');
    buffer.writeln('#EXT-X-TARGET-DURATION:10');
    buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');

    // Variant streams (quality levels)
    for (final quality in qualityLevels) {
      buffer
          .writeln('#EXT-X-STREAM-INF:BANDWIDTH=${quality.bitrateBps},'
              'RESOLUTION=${quality.width}x${quality.height}');
      buffer.writeln('$baseUrl/variant_${quality.width}x${quality.height}.m3u8');
    }

    return buffer.toString();
  }

  /// Generate variant playlist for specific quality level
  static String generateVariantPlaylist({
    required String segmentPrefix,
    required int totalSegments,
    required double targetDuration,
    required bool isFinal,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('#EXTM3U');
    buffer.writeln('#EXT-X-VERSION:3');
    buffer.writeln('#EXT-X-TARGET-DURATION:${targetDuration.ceil()}');
    buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');

    // Add segment entries
    for (int i = 0; i < totalSegments; i++) {
      buffer.writeln('#EXTINF:$targetDuration,');
      buffer.writeln('${segmentPrefix}_$i.ts');
    }

    if (isFinal) {
      buffer.writeln('#EXT-X-ENDLIST');
    }

    return buffer.toString();
  }
}

/// Quality selector based on network conditions
class QualitySelector {
  final _detector = BandwidthDetector();
  QualityLevel _currentQuality;
  final _listeners = <VoidCallback>[];

  QualitySelector({
    required QualityLevel initialQuality,
  }) : _currentQuality = initialQuality;

  QualityLevel get currentQuality => _currentQuality;

  /// Record bandwidth and auto-adjust quality
  void recordBandwidth(int bytesDownloaded) {
    _detector.recordBytes(bytesDownloaded);

    // Check if we should switch quality
    _maybeAdjustQuality();
  }

  /// Manually set quality
  void setQuality(QualityLevel quality) {
    if (_currentQuality != quality) {
      _currentQuality = quality;
      _notifyListeners();
    }
  }

  /// Force rebuffer wait before switching down
  void rebufferDetected() {
    // Switch to lower quality if rebuffering occurs
    final allProfiles = QualityProfiles.getAllProfiles();
    final currentIndex = allProfiles.indexOf(_currentQuality);
    if (currentIndex > 0) {
      setQuality(allProfiles[currentIndex - 1]);
    }
  }

  void _maybeAdjustQuality() {
    final bandwidthBps = _detector.estimateBandwidthBps();
    final availableProfiles = QualityProfiles.getBalancedProfiles();

    // Only switch if significantly different from current
    final overhead = _currentQuality.bitrateBps * 1.2;
    if (bandwidthBps > overhead || bandwidthBps < _currentQuality.bitrateBps * 0.5) {
      final bestQuality =
          BandwidthDetector.selectBestQuality(bandwidthBps, availableProfiles);
      setQuality(bestQuality);
    }
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  double getEstimatedBandwidthMbps() => _detector.estimateBandwidthMbps();
}

// Type alias for void callback
typedef VoidCallback = void Function();
