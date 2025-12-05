import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../services/xtream_service.dart';

/// Singleton Xtream service provider
final xtreamServiceProvider = Provider<XtreamService>((ref) {
  final service = XtreamService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current selected playlist provider
final selectedPlaylistProvider = StateProvider<PlaylistConfig?>((ref) => null);

/// Provider that watches for playlist changes and updates Xtream service
final activeXtreamServiceProvider = Provider<XtreamService>((ref) {
  final service = ref.watch(xtreamServiceProvider);
  final playlist = ref.watch(selectedPlaylistProvider);
  
  if (playlist != null) {
    service.setPlaylist(playlist);
  }
  
  return service;
});

/// Provider for live TV channels grouped by category
final liveChannelsProvider = FutureProvider.autoDispose((ref) async {
  final service = ref.watch(activeXtreamServiceProvider);
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
final epgProvider = FutureProvider.family.autoDispose((ref, String streamId) async {
  final service = ref.watch(activeXtreamServiceProvider);
  return await service.getShortEpg(streamId);
});
