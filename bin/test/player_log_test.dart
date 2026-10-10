import 'package:test/test.dart';
import '../api/player_log.dart';

void main() {
  group('formatPlayerEvent', () {
    test('écrit une coupure avec sa durée et le buffer', () {
      expect(
        formatPlayerEvent({
          'event': 'stall',
          'session': 'ab12',
          'ch': '554034',
          'ms': 5230,
          'buffer': 0.04,
        }),
        '[Player] stall session=ab12 ch=554034 ms=5230 buffer=0.0',
      );
    });

    test('refuse un événement inconnu ou un payload invalide', () {
      expect(formatPlayerEvent({'event': 'rm -rf'}), isNull);
      expect(formatPlayerEvent('stall'), isNull);
      expect(formatPlayerEvent(null), isNull);
    });

    test('pas d\'injection de lignes ni d\'URL (identifiants Xtream)', () {
      final line = formatPlayerEvent({
        'event': 'mpegts_error',
        'detail': 'NetworkError http://panel/live/user/pass/1.ts\n[Player] faux',
      })!;
      expect(line, isNot(contains('\n')));
      expect(line, isNot(contains('user/pass')));
      expect(line, contains('<url>'));
    });

    test('ignore les champs inattendus et les nombres non finis', () {
      final line = formatPlayerEvent({
        'event': 'seek',
        'from': 10,
        'to': double.infinity,
        'cookie': 'secret',
      })!;
      expect(line, contains('from=10'));
      expect(line, isNot(contains('to=')));
      expect(line, isNot(contains('secret')));
    });
  });
}
