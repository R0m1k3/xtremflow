import 'package:test/test.dart';
import '../services/gpu_fallback.dart';

void main() {
  group('isGpuFailure', () {
    test('detects NVENC out-of-memory', () {
      expect(
        isGpuFailure(
          'FFmpeg exited (1): [h264_nvenc @ 0x55] OpenEncodeSessionEx failed: '
          'out of memory (10)',
        ),
        isTrue,
      );
    });

    test('detects missing NVENC device', () {
      expect(
        isGpuFailure('[h264_nvenc @ 0x1] No capable devices found'),
        isTrue,
      );
    });

    test('detects CUDA errors', () {
      expect(
        isGpuFailure('cu->cuInit(0) failed -> CUDA_ERROR_OUT_OF_MEMORY'),
        isTrue,
      );
    });

    test('detects encoder opening failure', () {
      expect(
        isGpuFailure(
          'Error while opening encoder for output stream #0:0 - maybe '
          'incorrect parameters such as bit_rate, rate, width or height',
        ),
        isTrue,
      );
    });

    test('ignores upstream failures', () {
      expect(
        isGpuFailure(
          'FFmpeg exited (1): http://x/live/u/p/1.ts: Server returned 404 '
          'Not Found',
        ),
        isFalse,
      );
    });

    test('ignores timeouts and null', () {
      expect(isGpuFailure('Timeout waiting for transcoder'), isFalse);
      expect(isGpuFailure(null), isFalse);
    });
  });

  group('GpuHealth', () {
    test('available until a failure, then again after cooldown', () {
      var now = DateTime.utc(2026, 10, 8, 20, 0);
      final health = GpuHealth(
        cooldown: const Duration(minutes: 2),
        now: () => now,
      );

      expect(health.available, isTrue);

      health.markFailed();
      expect(health.available, isFalse);

      now = now.add(const Duration(minutes: 1, seconds: 59));
      expect(health.available, isFalse);

      now = now.add(const Duration(seconds: 1));
      expect(health.available, isTrue);
    });
  });
}
