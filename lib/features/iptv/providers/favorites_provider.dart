import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the list of favorite channel IDs
class FavoritesNotifier extends StateNotifier<List<String>> {
  FavoritesNotifier() : super([]) {
    _loadFavorites();
  }

  static const String _key = 'xtremflow_favorites';

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_key) ?? [];
    state = favorites;
  }

  Future<void> toggleFavorite(String streamId) async {
    final prefs = await SharedPreferences.getInstance();
    if (state.contains(streamId)) {
      state = state.where((id) => id != streamId).toList();
    } else {
      state = [...state, streamId];
    }
    await prefs.setStringList(_key, state);
  }

  bool isFavorite(String streamId) {
    return state.contains(streamId);
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
      return FavoritesNotifier();
    });

/// Favourite channel groups (« Favoris » of the Direct tab), per playlist.
///
/// Stored like the favourite channels, under [storageKey], one element per
/// group: `"<playlist id>:<category name>"` (a category name may itself
/// contain `:`; only the first one separates).
class FavoriteCategoriesNotifier extends StateNotifier<List<String>> {
  FavoriteCategoriesNotifier() : super([]) {
    _load();
  }

  static const String storageKey = 'xtremflow_favorite_categories';

  static String keyOf(String playlistId, String category) =>
      '$playlistId:$category';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(storageKey) ?? [];
    // A toggle made before the load finished wins over the stored list.
    state = [...saved, ...state.where((k) => !saved.contains(k))];
  }

  bool isFavorite(String playlistId, String category) =>
      state.contains(keyOf(playlistId, category));

  /// Pinned groups of [playlistId], in the order they were pinned.
  List<String> categoriesOf(String playlistId) {
    final prefix = '$playlistId:';
    return [
      for (final k in state)
        if (k.startsWith(prefix)) k.substring(prefix.length),
    ];
  }

  Future<void> toggle(String playlistId, String category) async {
    final key = keyOf(playlistId, category);
    state = state.contains(key)
        ? state.where((k) => k != key).toList()
        : [...state, key];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, state);
  }
}

final favoriteCategoriesProvider =
    StateNotifierProvider<FavoriteCategoriesNotifier, List<String>>(
      (ref) => FavoriteCategoriesNotifier(),
    );
