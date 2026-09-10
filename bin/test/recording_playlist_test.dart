import 'package:test/test.dart';
import '../api/recording_playlist.dart';

void main() {
  group('parseRecordingStart', () {
    test('reads a positive position in seconds', () {
      expect(parseRecordingStart('2700'), 2700);
    });

    test('truncates fractions of a second', () {
      expect(parseRecordingStart('2700.9'), 2700);
    });

    test('falls back to the beginning when absent or unusable', () {
      expect(parseRecordingStart(null), 0);
      expect(parseRecordingStart(''), 0);
      expect(parseRecordingStart('abc'), 0);
      expect(parseRecordingStart('-30'), 0);
      expect(parseRecordingStart('NaN'), 0);
      expect(parseRecordingStart('Infinity'), 0);
    });
  });

  group('recordingOffsetKey', () {
    test('round-trips through its parser', () {
      for (final start in [0, 1, 2700, 86400]) {
        expect(parseRecordingOffsetKey(recordingOffsetKey(start)), start);
      }
    });

    test('rejects keys that are not an offset', () {
      expect(parseRecordingOffsetKey('t'), isNull);
      expect(parseRecordingOffsetKey('segment_000.ts'), isNull);
      expect(parseRecordingOffsetKey('..'), isNull);
      expect(parseRecordingOffsetKey('t-30'), isNull);
      expect(parseRecordingOffsetKey('tabc'), isNull);
    });
  });

  group('rewriteRecordingPlaylist', () {
    const playlist = '#EXTM3U\n'
        '#EXT-X-VERSION:3\n'
        '#EXT-X-TARGETDURATION:4\n'
        '#EXT-X-PLAYLIST-TYPE:EVENT\n'
        '#EXTINF:4.000000,\n'
        'segment_000.ts\n'
        '#EXTINF:4.000000,\n'
        'segment_001.ts\n';

    test('binds every segment to its own session directory', () {
      final rewritten = rewriteRecordingPlaylist(playlist, 't2700');
      expect(rewritten, contains('t2700/segment_000.ts'));
      expect(rewritten, contains('t2700/segment_001.ts'));
      expect(rewritten, isNot(contains('\nsegment_')));
    });

    test('leaves tags untouched', () {
      final rewritten = rewriteRecordingPlaylist(playlist, 't0');
      expect(rewritten, startsWith('#EXTM3U\n#EXT-X-VERSION:3\n'));
      expect(rewritten, contains('#EXT-X-PLAYLIST-TYPE:EVENT'));
      expect('#EXTINF:4.000000,'.allMatches(rewritten).length, 2);
    });

    test('is idempotent on an already rewritten playlist', () {
      final once = rewriteRecordingPlaylist(playlist, 't60');
      expect(rewriteRecordingPlaylist(once, 't60'), once);
    });
  });
}
