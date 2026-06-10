/// Pure decision logic for the recording scheduler, extracted for testability.

enum RecordingAction {
  /// Start the recording now.
  start,

  /// Capacity reached but the window is still open: retry on a later tick.
  wait,

  /// The end time passed before the recording could start.
  fail,

  /// Not yet due — nothing to do.
  none,
}

/// Decides what to do with a scheduled recording on a scheduler tick.
RecordingAction decideRecordingAction({
  required DateTime now,
  required DateTime startTime,
  required DateTime endTime,
  required int activeCount,
  required int maxConcurrent,
}) {
  final nowUtc = now.toUtc();
  final startUtc = startTime.toUtc();
  final endUtc = endTime.toUtc();

  if (nowUtc.isAfter(endUtc)) return RecordingAction.fail;
  if (!nowUtc.isAfter(startUtc)) return RecordingAction.none;
  if (activeCount >= maxConcurrent) return RecordingAction.wait;
  return RecordingAction.start;
}
