import 'dart:async';

import 'package:test/test.dart';
import '../models/playlist_config.dart';
import '../services/upstream_slots.dart';

void main() {
  group('UpstreamSlots.makeRoom', () {
    late UpstreamSlots slots;
    late List<String> released;
    var clock = DateTime(2026, 1, 1);

    void add(String id, String account) {
      clock = clock.add(const Duration(seconds: 1));
      slots.register(id: id, account: account, release: () => released.add(id));
    }

    setUp(() {
      slots = UpstreamSlots(now: () => clock);
      released = [];
    });

    test('compte à 1 connexion : le flux précédent est coupé', () {
      add('live_1_source', 'acc');
      final freed = slots.makeRoom('acc', max: 1, keep: 'live_2_source');
      expect(freed, ['live_1_source']);
      expect(released, ['live_1_source']);
      expect(slots.countFor('acc'), 0);
    });

    test('la session demandée elle-même n\'est jamais coupée', () {
      add('live_1_source', 'acc');
      expect(slots.makeRoom('acc', max: 1, keep: 'live_1_source'), isEmpty);
      expect(released, isEmpty);
    });

    test('les plus anciennes partent d\'abord, dans la limite du quota', () {
      add('a', 'acc');
      add('b', 'acc');
      add('c', 'acc');
      // 3 connexions max : il faut une place pour la nouvelle → 1 seule coupée.
      expect(slots.makeRoom('acc', max: 3, keep: 'new'), ['a']);
      expect(slots.countFor('acc'), 2);
    });

    test('un autre compte n\'est jamais touché', () {
      add('x', 'other');
      expect(slots.makeRoom('acc', max: 1, keep: 'new'), isEmpty);
      expect(slots.countFor('other'), 1);
    });

    test('unregister avec un jeton périmé ne libère pas la session relancée', () {
      final old = slots.register(id: 's', account: 'acc', release: () {});
      slots.register(id: 's', account: 'acc', release: () {});
      slots.unregister('s', token: old);
      expect(slots.countFor('acc'), 1);
    });

    test('un flux encore regardé n\'est jamais coupé (pas de ping-pong entre deux lecteurs)', () {
      slots.register(
        id: 'watched',
        account: 'acc',
        release: () => released.add('watched'),
        isActive: () => true,
      );
      expect(slots.makeRoom('acc', max: 1, keep: 'new'), isEmpty);
      expect(released, isEmpty);
      expect(slots.countFor('acc'), 1);
    });

    test('seuls les orphelins partent, même plus récents qu\'un flux regardé', () {
      slots.register(
        id: 'watched',
        account: 'acc',
        release: () => released.add('watched'),
        isActive: () => true,
      );
      add('orphan', 'acc');
      expect(slots.makeRoom('acc', max: 1, keep: 'new'), ['orphan']);
      expect(released, ['orphan']);
    });

    test('quota inconnu ou nul : rien n\'est coupé', () {
      add('a', 'acc');
      expect(slots.makeRoom('acc', max: 0, keep: 'new'), isEmpty);
    });
  });

  group('AccountLimits', () {
    PlaylistConfig playlist() => PlaylistConfig(
          id: 'p',
          name: 'n',
          dns: 'http://panel.test',
          username: 'u',
          password: 'x',
          createdAt: DateTime(2026),
        );

    test('ne fait jamais attendre un flux : repli immédiat, valeur réelle ensuite', () async {
      final pending = Completer<int?>();
      final limits = AccountLimits(fetch: (_) => pending.future);

      // Le panneau répond lentement (4 s mesurées en prod) : le premier flux
      // part tout de suite sur la valeur de repli.
      expect(await limits.maxFor(playlist()), AccountLimits.fallback);

      pending.complete(3);
      await Future<void>.delayed(Duration.zero);
      expect(await limits.maxFor(playlist()), 3);
    });

    test('valeur périmée servie pendant le rafraîchissement', () async {
      var calls = 0;
      final limits = AccountLimits(
        ttl: Duration.zero,
        fetch: (_) async => ++calls == 1 ? 2 : 5,
      );
      await limits.maxFor(playlist());
      await Future<void>.delayed(Duration.zero);
      // Périmée (ttl nul) : la valeur connue sort sans attendre la nouvelle.
      expect(await limits.maxFor(playlist()), 2);
      await Future<void>.delayed(Duration.zero);
      expect(await limits.maxFor(playlist()), 5);
    });

    test('panneau en échec : repli, sans exception', () async {
      final limits = AccountLimits(fetch: (_) async => throw Exception('down'));
      expect(await limits.maxFor(playlist()), AccountLimits.fallback);
      await Future<void>.delayed(Duration.zero);
      expect(await limits.maxFor(playlist()), AccountLimits.fallback);
    });
  });

  group('parseMaxConnections', () {
    test('lit la valeur texte renvoyée par player_api', () {
      expect(
        parseMaxConnections({
          'user_info': {'max_connections': '1'},
        }),
        1,
      );
    });

    test('accepte un entier', () {
      expect(
        parseMaxConnections({
          'user_info': {'max_connections': 3},
        }),
        3,
      );
    });

    test('réponse inexploitable → null', () {
      expect(parseMaxConnections({'user_info': {}}), isNull);
      expect(parseMaxConnections('oops'), isNull);
      expect(
        parseMaxConnections({
          'user_info': {'max_connections': '0'},
        }),
        isNull,
      );
    });
  });
}
