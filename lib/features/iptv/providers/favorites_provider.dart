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

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  return FavoritesNotifier();
});
