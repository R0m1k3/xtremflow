import 'dart:async';

import 'package:test/test.dart';
import '../utils/stream_pipe.dart';

void main() {
  group('pipeWithBackpressure', () {
    test('relaie les données au client', () async {
      final source = StreamController<List<int>>();
      final piped = pipeWithBackpressure(source.stream, onStop: () {});

      final received = <List<int>>[];
      final done = piped.listen(received.add).asFuture<void>();

      source.add([1, 2, 3]);
      await source.close();
      await done;

      expect(received, [
        [1, 2, 3]
      ]);
    });

    test('propage la pause du client vers la source', () async {
      // Sans cette propagation, un client plus lent que le flux laissait
      // FFmpeg produire à pleine vitesse et le serveur empilait les paquets
      // en mémoire : latence qui dérive et lecture qui saccade.
      var paused = false;
      var resumed = false;
      final source = StreamController<List<int>>(
        onPause: () => paused = true,
        onResume: () => resumed = true,
      );

      final subscription = pipeWithBackpressure(
        source.stream,
        onStop: () {},
      ).listen((_) {});

      subscription.pause();
      await Future<void>.delayed(Duration.zero);
      expect(paused, isTrue);

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(resumed, isTrue);

      await subscription.cancel();
      await source.close();
    });

    test('arrête le producteur quand le client se déconnecte', () async {
      var stopped = 0;
      final source = StreamController<List<int>>();
      final subscription =
          pipeWithBackpressure(source.stream, onStop: () => stopped++)
              .listen((_) {});

      await subscription.cancel();

      expect(stopped, 1);
      await source.close();
    });

    test('arrête le producteur quand la source se termine', () async {
      var stopped = 0;
      final source = StreamController<List<int>>();
      final piped = pipeWithBackpressure(source.stream, onStop: () => stopped++);
      final done = piped.listen((_) {}).asFuture<void>();

      await source.close();
      await done;

      expect(stopped, 1);
    });
  });
}
