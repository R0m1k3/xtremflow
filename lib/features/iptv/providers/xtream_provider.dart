import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../services/xtream_service.dart';
import 'settings_provider.dart';

/// Family provider for Xtream service - one instance per playlist
final xtreamServiceProvider =
    Provider.family<XtreamService, PlaylistConfig>((ref, playlist) {
  final service = XtreamService();
  final settings = ref.read(iptvSettingsProvider);
  service.setBackendUrl(settings.backendUrl);
  service.updateTimeouts(settings.timeoutSeconds);
  service.setPlaylist(playlist);

  // Update instance without rebuilding the provider to keep connectivity active
  ref.listen(iptvSettingsProvider, (previous, next) {
    service.setBackendUrl(next.backendUrl);
    service.updateTimeouts(next.timeoutSeconds);
  });

  // ref.onDispose(() => service.dispose()); // Removed to prevent premature Dio destruction
  return service;
});

/// Singleton Xtream service provider (legacy, for activeXtreamServiceProvider)
final _singletonXtreamServiceProvider = Provider<XtreamService>((ref) {
  final service = XtreamService();
  final settings = ref.read(iptvSettingsProvider);
  service.setBackendUrl(settings.backendUrl);
  service.updateTimeouts(settings.timeoutSeconds);

  // Update instance without rebuilding the provider
  ref.listen(iptvSettingsProvider, (previous, next) {
    service.setBackendUrl(next.backendUrl);
    service.updateTimeouts(next.timeoutSeconds);
  });

  // ref.onDispose(() => service.dispose()); // Removed to prevent premature Dio destruction
  return service;
});

/// Current selected playlist provider with persistence for Web
final selectedPlaylistProvider = StateProvider<PlaylistConfig?>((ref) {
  // Restore from localStorage if on web
  try {
    final stored = html.window.localStorage['selected_playlist'];
    if (stored != null) {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      return PlaylistConfig.fromJson(data);
    }
  } catch (e) {
    debugPrint('Error restoring playlist: $e');
  }
  return null;
});

/// Préfixe des caches de catalogue (chaînes, films, séries) par IPTV.
const xtreamCachePrefix = 'xtream_cache_';

/// Vide les caches de catalogue pour rendre de la place.
///
/// Ces caches pèsent plusieurs mégaoctets par IPTV et saturent le quota du
/// navigateur ; ils se reconstruisent au prochain chargement.
void clearXtreamCaches() {
  final keys = html.window.localStorage.keys
      .where((k) => k.startsWith(xtreamCachePrefix))
      .toList();
  for (final key in keys) {
    html.window.localStorage.remove(key);
  }
}

/// Écrit l'IPTV courante là où `AuthedHttp` la relit pour poser l'en-tête
/// `X-Playlist-Id`.
///
/// Quota saturé, `setItem` lève : les caches de catalogue remplissent le
/// stockage et faisaient échouer cette écriture-ci, minuscule mais décisive.
/// L'entrée restait sur l'IPTV précédente, l'en-tête désignait la mauvaise
/// playlist, et les deux IPTV retombaient sur la même. Le catalogue cède donc
/// la place, et un échec résiduel ne doit jamais empêcher le changement
/// d'IPTV.
void persistSelectedPlaylist(PlaylistConfig? playlist) {
  if (playlist == null) {
    try {
      html.window.localStorage.remove('selected_playlist');
    } catch (_) {}
    return;
  }
  final value = jsonEncode(playlist.toJson());
  try {
    html.window.localStorage['selected_playlist'] = value;
  } catch (_) {
    try {
      clearXtreamCaches();
      html.window.localStorage['selected_playlist'] = value;
    } catch (e) {
      debugPrint('Impossible de persister l\'IPTV choisie: $e');
    }
  }
}

/// Choisit l'IPTV courante et la persiste dans le même temps.
///
/// Écrire par le seul `playlistPersistenceProvider` ne suffit pas : son
/// `ref.listen` n'existe qu'une fois `activeXtreamServiceProvider` lu, c'est
/// à dire une fois le tableau de bord construit. Le tout premier choix d'une
/// session partait donc sans être écrit, `AuthedHttp` n'envoyait aucun
/// en-tête, et le serveur repliait sur la playlist la plus récente — les deux
/// IPTV retombaient alors sur la même, d'où une seule règle Auto NBA pour
/// les deux.
void selectPlaylist(WidgetRef ref, PlaylistConfig playlist) {
  persistSelectedPlaylist(playlist);
  ref.read(selectedPlaylistProvider.notifier).state = playlist;
}

// Listener to save selected playlist
final playlistPersistenceProvider = Provider<void>((ref) {
  ref.listen(selectedPlaylistProvider, (previous, next) {
    persistSelectedPlaylist(next);
  });
});

/// Provider that watches for playlist changes and updates Xtream service
final activeXtreamServiceProvider = Provider<XtreamService>((ref) {
  final service = ref.watch(_singletonXtreamServiceProvider);
  final playlist = ref.watch(selectedPlaylistProvider);

  // Ensure persistence listener is active
  ref.read(playlistPersistenceProvider);

  if (playlist != null) {
    service.setPlaylist(playlist);
    final settings = ref.read(iptvSettingsProvider);
    service.updateTimeouts(settings.timeoutSeconds);
  }

  return service;
});

/// Provider for live TV channels grouped by category
final liveChannelsProvider = FutureProvider.autoDispose((ref) async {
  final service = ref.watch(activeXtreamServiceProvider);
  return await service.getLiveChannels();
});

/// Provider for live TV channels by playlist (family provider)
final liveChannelsByPlaylistProvider =
    FutureProvider.family.autoDispose((ref, PlaylistConfig playlist) async {
  final service = ref.watch(xtreamServiceProvider(playlist));
  return await service.getLiveChannels();
});

/// Provider for VOD items (movies) grouped by category
final vodItemsProvider = FutureProvider.autoDispose((ref) async {
  final service = ref.watch(activeXtreamServiceProvider);
  return await service.getVodItems();
});

/// Provider for series grouped by category
final seriesProvider = FutureProvider.autoDispose((ref) async {
  final service = ref.watch(activeXtreamServiceProvider);
  return await service.getSeries();
});

/// Provider for EPG of a specific stream
final epgProvider =
    FutureProvider.family.autoDispose((ref, String streamId) async {
  final service = ref.watch(activeXtreamServiceProvider);
  return await service.getShortEpg(streamId);
});

/// EPG request key for family provider (combines playlist and streamId)
class EpgRequestKey {
  final PlaylistConfig playlist;
  final String streamId;

  const EpgRequestKey({required this.playlist, required this.streamId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpgRequestKey &&
          runtimeType == other.runtimeType &&
          playlist == other.playlist &&
          streamId == other.streamId;

  @override
  int get hashCode => playlist.hashCode ^ streamId.hashCode;
}

/// Provider for EPG with playlist context
final epgByPlaylistProvider =
    FutureProvider.family.autoDispose((ref, EpgRequestKey key) async {
  final service = ref.watch(xtreamServiceProvider(key.playlist));
  return await service.getShortEpg(key.streamId);
});
