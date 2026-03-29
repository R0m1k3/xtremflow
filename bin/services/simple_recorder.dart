import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

/// 🎯 SIMPLIFIED Recording System - One job: Record streams
class SimpleRecorder {
  final AppDatabase db;
  final String recordingsDir;

  // Active recordings (streamId -> process)
  final Map<String, _ActiveRecording> _active = {};

  SimpleRecorder(this.db, {this.recordingsDir = '/app/recordings'});

  /// Initialize recordings directory
  Future<void> init() async {
    final dir = Directory(recordingsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    print('🎬 Recorder ready -> $recordingsDir');
  }

  /// Start recording immediately
  Future<String> startRecording({
    required String channelId,
    required String streamUrl,
    required String title,
    required Duration duration,
  }) async {
    if (_active.containsKey(channelId)) {
      throw Exception('Already recording: $title');
    }

    final recordingId = const Uuid().v4();
    final now = DateTime.now();
    final endTime = now.add(duration);

    // Create recording in DB
    db.createRecording(
      userId: 'system',
      channelId: channelId,
      streamUrl: streamUrl,
      title: title,
      startTime: now,
      endTime: endTime,
    );

    // Generate safe filename
    final filename = _safeName(title, recordingId);
    final filepath = '$recordingsDir/$filename';

    // Start FFmpeg process
    try {
      final ffmpeg = await Process.start('ffmpeg', [
        '-y',
        '-i',
        streamUrl,
        '-c',
        'copy',
        '-t',
        '${duration.inSeconds}',
        filepath,
      ]);

      _active[channelId] = _ActiveRecording(
        id: recordingId,
        process: ffmpeg,
        filepath: filepath,
        endTime: endTime,
      );

      // Update DB
      db.updateRecordingStatus(recordingId, 'recording', filePath: filepath);

      // Auto-stop when time is up or process ends
      ffmpeg.exitCode.then((_) {
        db.updateRecordingStatus(recordingId, 'completed');
        _active.remove(channelId);
        print('✅ Recording done: $title');
      }).catchError((e) {
        db.updateRecordingStatus(recordingId, 'failed',
            errorReason: 'FFmpeg error');
        _active.remove(channelId);
      });

      print('🔴 Recording: $title ($duration)');
      return recordingId;
    } catch (e) {
      db.updateRecordingStatus(recordingId, 'failed', errorReason: '$e');
      rethrow;
    }
  }

  /// Schedule recording for later
  Future<String> scheduleRecording({
    required String channelId,
    required String streamUrl,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final recordingId = const Uuid().v4();

    // Create in DB with 'scheduled' status
    db.createRecording(
      userId: 'system',
      channelId: channelId,
      streamUrl: streamUrl,
      title: title,
      startTime: startTime,
      endTime: endTime,
    );

    // Schedule auto-start
    final delay = startTime.difference(DateTime.now());
    if (delay.isNegative) {
      throw Exception('Start time is in the past');
    }

    Timer(delay, () async {
      try {
        await startRecording(
          channelId: channelId,
          streamUrl: streamUrl,
          title: title,
          duration: endTime.difference(startTime),
        );
      } catch (e) {
        print('❌ Auto-start failed: $e');
      }
    });

    print('⏰ Scheduled: $title at ${startTime.toLocal()}');
    return recordingId;
  }

  /// Stop recording immediately
  Future<void> stopRecording(String channelId) async {
    final active = _active[channelId];
    if (active == null) return;

    active.process.kill();
    db.updateRecordingStatus(active.id, 'completed');
    _active.remove(channelId);
    print('⏹️  Stopped: $channelId');
  }

  /// Check scheduled recordings (call every minute)
  Future<void> checkScheduled() async {
    final now = DateTime.now();
    for (final rec in db.getAllRecordings()) {
      if (rec.status != 'scheduled') continue;
      if (now.isBefore(rec.startTime)) continue;

      try {
        await startRecording(
          channelId: rec.channelId,
          streamUrl: rec.streamUrl,
          title: rec.title,
          duration: rec.endTime.difference(rec.startTime),
        );
      } catch (e) {
        print('❌ Auto-start error: $e');
        db.updateRecordingStatus(rec.id, 'failed', errorReason: '$e');
      }
    }
  }

  /// Get active recordings
  List<Map<String, dynamic>> getActive() {
    return _active.entries
        .map(
          (e) => {
            'id': e.value.id,
            'channel': e.key,
            'filepath': e.value.filepath,
            'endsAt': e.value.endTime.toIso8601String(),
          },
        )
        .toList();
  }

  /// Cleanup old recordings (keep last 20)
  Future<void> cleanupOld({int keepCount = 20}) async {
    final dir = Directory(recordingsDir);
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    if (files.length > keepCount) {
      for (final file in files.skip(keepCount)) {
        await file.delete();
        print('🗑️  Deleted: ${file.path}');
      }
    }
  }

  String _safeName(String title, String id) {
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '').split('.')[0];
    return '${safe}_$timestamp.mkv';
  }

  void dispose() {
    for (final rec in _active.values) {
      rec.process.kill();
    }
  }
}

/// Internal: Active recording tracking
class _ActiveRecording {
  final String id;
  final Process process;
  final String filepath;
  final DateTime endTime;

  _ActiveRecording({
    required this.id,
    required this.process,
    required this.filepath,
    required this.endTime,
  });
}
