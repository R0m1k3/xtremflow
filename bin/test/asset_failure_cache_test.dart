import 'package:test/test.dart';
import '../api/asset_failure_cache.dart';

void main() {
  group('AssetFailureCache', () {
    test('un hôte inconnu est considéré joignable', () {
      final cache = AssetFailureCache();
      expect(cache.isDown('cdn.example'), isFalse);
    });

    test('un échec isolé ne coupe pas l’hôte', () {
      // Un 5xx passager ne doit pas priver l'utilisateur de ses logos
      // pendant plusieurs minutes.
      final cache = AssetFailureCache(threshold: 3);
      cache.recordFailure('cdn.example');
      expect(cache.isDown('cdn.example'), isFalse);
    });

    test('coupe l’hôte après le seuil d’échecs consécutifs', () {
      final cache = AssetFailureCache(threshold: 3);
      for (var i = 0; i < 3; i++) {
        cache.recordFailure('cdn.example');
      }
      expect(cache.isDown('cdn.example'), isTrue);
    });

    test('un succès remet le compteur à zéro', () {
      final cache = AssetFailureCache(threshold: 3);
      cache.recordFailure('cdn.example');
      cache.recordFailure('cdn.example');
      cache.recordSuccess('cdn.example');
      cache.recordFailure('cdn.example');
      expect(cache.isDown('cdn.example'), isFalse);
    });

    test('la coupure expire après le TTL', () {
      var now = DateTime(2026, 9, 19, 9);
      final cache = AssetFailureCache(
        threshold: 1,
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );
      cache.recordFailure('cdn.example');
      expect(cache.isDown('cdn.example'), isTrue);

      now = now.add(const Duration(minutes: 6));
      expect(cache.isDown('cdn.example'), isFalse);
    });

    test('les hôtes sont indépendants', () {
      final cache = AssetFailureCache(threshold: 1);
      cache.recordFailure('mort.example');
      expect(cache.isDown('mort.example'), isTrue);
      expect(cache.isDown('vivant.example'), isFalse);
    });
  });
}
