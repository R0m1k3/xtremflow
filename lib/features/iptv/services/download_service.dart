import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a download task
class DownloadTask {
  final String id;
  final String title;
  final String url;
  final String filePath;
  final DownloadStatus status;
  final double progress;
  final int? totalSize;
  final int downloadedSize;

  DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.filePath,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.totalSize,
    this.downloadedSize = 0,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedSize,
  }) =>
      DownloadTask(
        id: id,
        title: title,
        url: url,
        filePath: filePath,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        totalSize: totalSize,
        downloadedSize: downloadedSize ?? this.downloadedSize,
      );
}

enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Service for managing downloads
class DownloadService {
  static const _downloadDir = './downloads';
  static const _maxConcurrentDownloads = 3;
  static const _maxStorageGb = 50;

  final List<DownloadTask> _downloads = [];
  final List<String> _activeDownloads = [];

  /// Initialize download directory
  static Future<void> initialize() async {
    final dir = Directory(_downloadDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }

  /// Start a new download
  Future<DownloadTask> startDownload({
    required String id,
    required String title,
    required String url,
  }) async {
    final filePath = '$_downloadDir/$id.mp4';
    final task = DownloadTask(
      id: id,
      title: title,
      url: url,
      filePath: filePath,
    );

    _downloads.add(task);
    _processDownloadQueue();
    return task;
  }

  /// Pause download
  void pauseDownload(String id) {
    final index = _downloads.indexWhere((t) => t.id == id);
    if (index != -1) {
      _downloads[index] = _downloads[index].copyWith(
        status: DownloadStatus.paused,
      );
    }
  }

  /// Resume download
  void resumeDownload(String id) {
    final index = _downloads.indexWhere((t) => t.id == id);
    if (index != -1) {
      _downloads[index] = _downloads[index].copyWith(
        status: DownloadStatus.pending,
      );
      _processDownloadQueue();
    }
  }

  /// Cancel download
  void cancelDownload(String id) {
    final index = _downloads.indexWhere((t) => t.id == id);
    if (index != -1) {
      _downloads.removeAt(index);
      _activeDownloads.remove(id);
    }
  }

  /// Get all downloads
  List<DownloadTask> getAllDownloads() => List.from(_downloads);

  /// Get download progress
  double getDownloadProgress(String id) {
    final task = _downloads.firstWhere((t) => t.id == id, orElse: () => DownloadTask(
      id: id,
      title: '',
      url: '',
      filePath: '',
    ));
    return task.progress;
  }

  /// Get available storage
  Future<int> getAvailableStorage() async {
    final dir = Directory(_downloadDir);
    if (!dir.existsSync()) return _maxStorageGb * 1024 * 1024 * 1024;

    int totalSize = 0;
    final files = dir.listSync(recursive: true);
    for (final file in files) {
      if (file is File) {
        totalSize += file.lengthSync();
      }
    }

    return (_maxStorageGb * 1024 * 1024 * 1024) - totalSize;
  }

  /// Clean up old downloads based on space
  Future<void> cleanupOldDownloads() async {
    final available = await getAvailableStorage();
    if (available < 1024 * 1024 * 1024) {
      // Less than 1GB free
      final dir = Directory(_downloadDir);
      final files = dir.listSync()
          .whereType<File>()
          .toList();

      // Sort by modification time, delete oldest first
      files.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));

      for (final file in files.take(files.length ~/ 3)) {
        try {
          file.deleteSync();
        } catch (e) {
          print('Error deleting file: $e');
        }
      }
    }
  }

  /// Process download queue
  Future<void> _processDownloadQueue() async {
    while (_activeDownloads.length < _maxConcurrentDownloads) {
      final pendingIndex =
          _downloads.indexWhere((t) => t.status == DownloadStatus.pending);
      if (pendingIndex == -1) break;

      final task = _downloads[pendingIndex];
      _activeDownloads.add(task.id);

      _downloads[pendingIndex] =
          task.copyWith(status: DownloadStatus.downloading);

      try {
        await _downloadFile(task);
      } catch (e) {
        print('Download error: $e');
        final index = _downloads.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _downloads[index] =
              _downloads[index].copyWith(status: DownloadStatus.failed);
        }
      } finally {
        _activeDownloads.remove(task.id);
      }
    }
  }

  /// Download file with progress tracking
  Future<void> _downloadFile(DownloadTask task) async {
    // Simplified version - in production use dio or http with progress tracking
    final file = File(task.filePath);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }

    // Stream download and update progress
    // This is a placeholder - implement with actual download logic
    for (int i = 0; i <= 100; i++) {
      final index = _downloads.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _downloads[index] = _downloads[index].copyWith(
          progress: i.toDouble(),
        );
      }

      // Check if paused or cancelled
      final currentTask = _downloads.firstWhere((t) => t.id == task.id, orElse: () => task);
      if (currentTask.status == DownloadStatus.paused ||
          !_activeDownloads.contains(task.id)) {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Mark as completed
    final index = _downloads.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _downloads[index] = _downloads[index].copyWith(
        status: DownloadStatus.completed,
        progress: 100.0,
      );
    }
  }

  /// Check if file is available for offline playback
  bool isAvailableOffline(String id) {
    final task = _downloads.firstWhere(
      (t) => t.id == id,
      orElse: () => DownloadTask(
        id: id,
        title: '',
        url: '',
        filePath: '',
      ),
    );
    if (task.status == DownloadStatus.completed) {
      return File(task.filePath).existsSync();
    }
    return false;
  }

  /// Get file path for offline content
  String? getOfflineFilePath(String id) {
    final task = _downloads.firstWhere(
      (t) => t.id == id && t.status == DownloadStatus.completed,
      orElse: () => DownloadTask(
        id: id,
        title: '',
        url: '',
        filePath: '',
      ),
    );

    if (File(task.filePath).existsSync()) {
      return task.filePath;
    }
    return null;
  }
}

// Riverpod providers

final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService();
});

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadTask>>((ref) {
  return DownloadsNotifier();
});

class DownloadsNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadsNotifier() : super([]);

  void addDownload(DownloadTask task) {
    state = [...state, task];
  }

  void updateDownload(DownloadTask task) {
    state = [
      for (final d in state)
        if (d.id == task.id) task else d,
    ];
  }

  void removeDownload(String id) {
    state = state.where((d) => d.id != id).toList();
  }

  void clearCompleted() {
    state = state
        .where((d) => d.status != DownloadStatus.completed)
        .toList();
  }
}
