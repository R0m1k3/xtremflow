import 'dart:io';
import 'dart:async';

class CleanupService {
  final List<Directory> _targetDirectories = [];
  Timer? _timer;
  final Duration _defaultMaxAge;

  CleanupService({Duration defaultMaxAge = const Duration(hours: 24)})
      : _defaultMaxAge = defaultMaxAge;

  /// Add a directory to be monitored
  void addTarget(Directory dir) {
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
        print('CleanupService: Created missing directory: ${dir.path}');
      } catch (e) {
        print('CleanupService: Should monitor ${dir.path} but it does not exist and could not be created: $e');
        return;
      }
    }
    _targetDirectories.add(dir);
    print('CleanupService: Monitoring ${dir.path}');
  }

  /// Start the periodic cleanup task
  void start({Duration interval = const Duration(hours: 6)}) {
    _timer?.cancel();
    print('CleanupService: Starting scheduler (Interval: ${interval.inHours}h)');
    
    // Run immediately on start
    runCleanup();

    _timer = Timer.periodic(interval, (_) => runCleanup());
  }

  /// Stop the scheduler
  void stop() {
    _timer?.cancel();
    print('CleanupService: Scheduler stopped');
  }

  /// Trigger a manual cleanup
  Future<Map<String, dynamic>> runCleanup() async {
    print('CleanupService: Running cleanup task...');
    int deletedCount = 0;
    int freedBytes = 0;
    List<String> errors = [];

    for (final dir in _targetDirectories) {
      if (!dir.existsSync()) continue;

      try {
        final result = await _cleanDirectory(dir, _defaultMaxAge);
        deletedCount += result.count;
        freedBytes += result.bytes;
      } catch (e) {
        print('CleanupService: Error processing ${dir.path}: $e');
        errors.add('Error in ${dir.path}: $e');
      }
    }

    final summary = {
      'status': 'complete',
      'deleted_files': deletedCount,
      'freed_bytes': freedBytes,
      'timestamp': DateTime.now().toIso8601String(),
      'errors': errors,
    };

    print('CleanupService: Cleanup complete. Deleted $deletedCount files, freed ${(freedBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    return summary;
  }

  Future<({int count, int bytes})> _cleanDirectory(Directory dir, Duration maxAge) async {
    int count = 0;
    int bytes = 0;
    final now = DateTime.now();
    final threshold = now.subtract(maxAge);

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            // Check Modified AND Accessed time (if available) to be safe
            // Ideally we use modified time for temp files
            if (stat.modified.isBefore(threshold)) {
              final fileSize = stat.size;
              await entity.delete();
              count++;
              bytes += fileSize;
              // print('CleanupService: Deleted ${entity.path} (Age: ${now.difference(stat.modified).inHours}h)');
            }
          } catch (e) {
            // Ignore individual file errors (locked files etc)
            // print('CleanupService: Failed to delete ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      print('CleanupService: Failed to list ${dir.path}: $e');
      rethrow;
    }

    return (count: count, bytes: bytes);
  }
}
