import 'package:test/test.dart';
import '../api/streaming_handler.dart';

void main() {
  group('liveInputArgs', () {
    test('HLS : jamais de reconnect_at_eof (chaque segment finit par un EOF)',
        () {
      final args = liveInputArgs('http://p/live/u/p/1.m3u8', hls: true);
      expect(args, isNot(contains('-reconnect_at_eof')));
      expect(args, isNot(contains('-reconnect_streamed')));
    });

    test('HLS : démarre deux segments avant le direct pour avoir de l\'avance',
        () {
      final args = liveInputArgs('http://p/live/u/p/1.m3u8', hls: true);
      final i = args.indexOf('-live_start_index');
      expect(i, isNot(-1));
      expect(args[i + 1], '-2');
      // Option de démuxeur : doit précéder -i.
      expect(i, lessThan(args.indexOf('-i')));
    });

    test('.ts : garde la reconnexion en fin de flux (coupures du panneau)', () {
      final args = liveInputArgs('http://p/live/u/p/1.ts', hls: false);
      expect(args, contains('-reconnect_at_eof'));
      expect(args, isNot(contains('-live_start_index')));
    });

    test('l\'URL est la dernière entrée, juste après -i', () {
      final args = liveInputArgs('http://p/x.m3u8', hls: true);
      expect(args.last, 'http://p/x.m3u8');
      expect(args[args.length - 2], '-i');
    });
  });
}
