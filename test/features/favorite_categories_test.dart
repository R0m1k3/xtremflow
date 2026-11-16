import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xtremflow/features/iptv/providers/favorites_provider.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toggle adds then removes a group, stored as playlistId:name', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(favoriteCategoriesProvider.notifier);
    await _settle();

    await n.toggle('p1', 'FR | Sport');
    expect(c.read(favoriteCategoriesProvider), ['p1:FR | Sport']);
    expect(n.isFavorite('p1', 'FR | Sport'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(FavoriteCategoriesNotifier.storageKey), [
      'p1:FR | Sport',
    ]);

    await n.toggle('p1', 'FR | Sport');
    expect(c.read(favoriteCategoriesProvider), isEmpty);
    expect(prefs.getStringList(FavoriteCategoriesNotifier.storageKey), isEmpty);
  });

  test('reloads what was stored', () async {
    SharedPreferences.setMockInitialValues({
      FavoriteCategoriesNotifier.storageKey: ['p1:Cinéma', 'p2:Sport'],
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(favoriteCategoriesProvider);
    await _settle();
    expect(c.read(favoriteCategoriesProvider), ['p1:Cinéma', 'p2:Sport']);
  });

  test('two playlists are kept apart', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(favoriteCategoriesProvider.notifier);
    await _settle();

    await n.toggle('p1', 'Sport');
    await n.toggle('p2', 'Sport');
    await n.toggle('p2', 'UK: News');
    expect(n.categoriesOf('p1'), ['Sport']);
    expect(n.categoriesOf('p2'), ['Sport', 'UK: News']);
    expect(n.isFavorite('p1', 'UK: News'), isFalse);

    await n.toggle('p1', 'Sport');
    expect(n.categoriesOf('p1'), isEmpty);
    expect(n.isFavorite('p2', 'Sport'), isTrue);
  });
}
