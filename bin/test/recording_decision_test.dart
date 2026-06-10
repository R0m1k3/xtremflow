import 'package:test/test.dart';
import '../services/recording_decision.dart';

void main() {
  final now = DateTime.utc(2026, 6, 10, 12, 0);

  group('decideRecordingAction', () {
    test('starts when due and capacity available', () {
      expect(
        decideRecordingAction(
          now: now,
          startTime: now.subtract(const Duration(minutes: 1)),
          endTime: now.add(const Duration(hours: 1)),
          activeCount: 0,
          maxConcurrent: 2,
        ),
        RecordingAction.start,
      );
    });

    test('waits (keeps scheduled) when at capacity but window still open', () {
      expect(
        decideRecordingAction(
          now: now,
          startTime: now.subtract(const Duration(minutes: 1)),
          endTime: now.add(const Duration(hours: 1)),
          activeCount: 2,
          maxConcurrent: 2,
        ),
        RecordingAction.wait,
      );
    });

    test('fails when the end time has passed', () {
      expect(
        decideRecordingAction(
          now: now,
          startTime: now.subtract(const Duration(hours: 2)),
          endTime: now.subtract(const Duration(minutes: 5)),
          activeCount: 0,
          maxConcurrent: 2,
        ),
        RecordingAction.fail,
      );
    });

    test('does nothing before the start time', () {
      expect(
        decideRecordingAction(
          now: now,
          startTime: now.add(const Duration(minutes: 30)),
          endTime: now.add(const Duration(hours: 1)),
          activeCount: 0,
          maxConcurrent: 2,
        ),
        RecordingAction.none,
      );
    });

    test('second overlapping recording starts when maxConcurrent is 2', () {
      expect(
        decideRecordingAction(
          now: now,
          startTime: now.subtract(const Duration(minutes: 1)),
          endTime: now.add(const Duration(hours: 1)),
          activeCount: 1,
          maxConcurrent: 2,
        ),
        RecordingAction.start,
      );
    });
  });
}
