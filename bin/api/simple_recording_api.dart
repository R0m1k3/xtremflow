import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';
import '../services/simple_recorder.dart';

/// 🎯 Simple Recording API - 3 endpoints only!
class SimpleRecordingApi {
  final AppDatabase db;
  final SimpleRecorder recorder;

  SimpleRecordingApi(this.db, this.recorder);

  /// Setup routes
  Router get router {
    final router = Router();
    
    router.post('/record/now', _recordNow);
    router.post('/record/schedule', _scheduleRecord);
    router.post('/record/stop/<channelId>', _stopRecord);
    router.get('/record/list', _listRecordings);
    router.get('/record/active', _getActive);
    
    return router;
  }

  /// 🟢 POST /record/now
  /// Start recording RIGHT NOW
  /// Body: { channel_id, stream_url, title, duration_minutes }
  Future<Response> _recordNow(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString());
      
      final id = await recorder.startRecording(
        channelId: data['channel_id'],
        streamUrl: data['stream_url'],
        title: data['title'] ?? 'Recording',
        duration: Duration(minutes: data['duration_minutes'] ?? 60),
      );

      return Response.ok(
        jsonEncode({
          'status': 'recording',
          'id': id,
          'message': 'Recording started!',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 🔵 POST /record/schedule
  /// Schedule recording for later
  /// Body: { channel_id, stream_url, title, start_time (ISO), end_time (ISO) }
  Future<Response> _scheduleRecord(Request request) async {
    try {
      final data = jsonDecode(await request.readAsString());
      
      final id = await recorder.scheduleRecording(
        channelId: data['channel_id'],
        streamUrl: data['stream_url'],
        title: data['title'] ?? 'Recording',
        startTime: DateTime.parse(data['start_time']),
        endTime: DateTime.parse(data['end_time']),
      );

      return Response.ok(
        jsonEncode({
          'status': 'scheduled',
          'id': id,
          'message': 'Recording scheduled!',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 🔴 POST /record/stop/<channelId>
  /// Stop recording immediately
  Future<Response> _stopRecord(Request request, String channelId) async {
    try {
      await recorder.stopRecording(channelId);
      return Response.ok(
        jsonEncode({'status': 'stopped', 'message': 'Recording stopped!'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 📋 GET /record/list
  /// List all recordings
  Response _listRecordings(Request request) {
    final recordings = db.getAllRecordings();
    return Response.ok(
      jsonEncode({
        'total': recordings.length,
        'recordings': recordings.map((r) => r.toMap()).toList(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// 🟢 GET /record/active
  /// List currently recording
  Response _getActive(Request request) {
    return Response.ok(
      jsonEncode({
        'active': recorder.getActive(),
        'count': recorder.getActive().length,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
