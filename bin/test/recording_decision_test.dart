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

  group('decideOrphanAction', () {
    test('resumes while the window is still open', () {
      expect(
        decideOrphanAction(
          now: now,
          endTime: now.add(const Duration(minutes: 30)),
          hasFile: true,
        ),
        OrphanAction.resume,
      );
    });

    test('resumes even without a file (crash before the first byte)', () {
      expect(
        decideOrphanAction(
          now: now,
          endTime: now.add(const Duration(minutes: 30)),
          hasFile: false,
        ),
        OrphanAction.resume,
      );
    });

    test('keeps a partial file when the window has closed', () {
      expect(
        decideOrphanAction(
          now: now,
          endTime: now.subtract(const Duration(minutes: 5)),
          hasFile: true,
        ),
        OrphanAction.finish,
      );
    });

    test('fails when the window has closed with nothing captured', () {
      expect(
        decideOrphanAction(
          now: now,
          endTime: now.subtract(const Duration(minutes: 5)),
          hasFile: false,
        ),
        OrphanAction.fail,
      );
    });

    test('does not resume for the last seconds of the window', () {
      expect(
        decideOrphanAction(
          now: now,
          endTime: now.add(const Duration(seconds: 20)),
          hasFile: true,
        ),
        OrphanAction.finish,
      );
    });
  });

  group('decidePostExitAction', () {
    test('retries when ffmpeg dies mid-window', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now.add(const Duration(minutes: 40)),
          exitCode: 1,
          consecutiveFailures: 0,
          hasFile: true,
        ),
        PostExitAction.retry,
      );
    });

    test('retries on a clean exit too (upstream ended early)', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now.add(const Duration(minutes: 40)),
          exitCode: 0,
          consecutiveFailures: 2,
          hasFile: true,
        ),
        PostExitAction.retry,
      );
    });

    test('stops retrying once the attempt budget is spent', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now.add(const Duration(minutes: 40)),
          exitCode: 1,
          consecutiveFailures: maxFfmpegAttempts - 1,
          hasFile: true,
        ),
        PostExitAction.complete,
      );
    });

    test('completes at the end of the window', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now,
          exitCode: 0,
          consecutiveFailures: 0,
          hasFile: true,
        ),
        PostExitAction.complete,
      );
    });

    test('completes when ffmpeg errored but a file was captured', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now,
          exitCode: 1,
          consecutiveFailures: 0,
          hasFile: true,
        ),
        PostExitAction.complete,
      );
    });

    test('fails when nothing was captured and the window is over', () {
      expect(
        decidePostExitAction(
          now: now,
          endTime: now,
          exitCode: 1,
          consecutiveFailures: 0,
          hasFile: false,
        ),
        PostExitAction.fail,
      );
    });
  });

  group('captureDuration', () {
    test('uses the time left until the scheduled end, not the planned length',
        () {
      // Démarrage avec 2 minutes de retard sur une fenêtre d'une heure.
      expect(
        captureDuration(
          now: now,
          endTime: now.add(const Duration(minutes: 58)),
        ),
        const Duration(minutes: 58),
      );
    });

    test('never asks ffmpeg for a zero or negative duration', () {
      expect(
        captureDuration(
          now: now,
          endTime: now.subtract(const Duration(minutes: 5)),
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('ffmpegRetryDelay', () {
    test('backs off on repeated failures and caps at 30s', () {
      expect(ffmpegRetryDelay(1), const Duration(seconds: 3));
      expect(ffmpegRetryDelay(2), const Duration(seconds: 6));
      expect(ffmpegRetryDelay(3), const Duration(seconds: 12));
      expect(ffmpegRetryDelay(4), const Duration(seconds: 24));
      expect(ffmpegRetryDelay(5), const Duration(seconds: 30));
      expect(ffmpegRetryDelay(20), const Duration(seconds: 30));
    });
  });
}
