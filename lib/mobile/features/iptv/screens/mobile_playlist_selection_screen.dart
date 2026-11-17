import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../core/services/playlist_api_service.dart';
import '../../../../core/api/authed_http.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/glass.dart';
import '../../../../core/widgets/xtremflow_mark.dart';
import '../../../theme/mobile_theme.dart';

final playlistsProvider = FutureProvider<List<PlaylistConfig>>((ref) async {
  final service = PlaylistApiService();
  return service.getPlaylists();
});

class MobilePlaylistSelectionScreen extends ConsumerWidget {
  const MobilePlaylistSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Theme(
      data: MobileTheme.darkTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const XtremFlowWordmark(),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Se déconnecter',
                        icon: const Icon(
                          Icons.logout,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () async {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) {
                            context.go('/login');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                  child: Text(
                    'Playlists',
                    style: AppTheme.display(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Choisissez l’IPTV à regarder',
                    style: AppTheme.body(
                      fontSize: 15,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(child: _buildBody(context, ref, playlistsAsync)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PlaylistConfig>> playlistsAsync,
  ) {
    return playlistsAsync.when(
      loading: () => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            FutureBuilder(
              future: Future.delayed(const Duration(seconds: 5)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return TextButton(
                    onPressed: () => ref.refresh(playlistsProvider),
                    child: const Text('Toujours en chargement ? Réessayer'),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger les playlists',
              style: AppTheme.body(fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.refresh(playlistsProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
      data: (playlists) {
        if (playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.playlist_remove,
                  size: 44,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Aucune playlist disponible',
                  style: AppTheme.body(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: playlists.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return _MobilePlaylistCard(
              playlist: playlist,
              onTap: () {
                AuthedHttp.usePlaylist(playlist.id, json: playlist.toJson());
                // Choix + persistance dans le même geste : l'en-tête
                // X-Playlist-Id doit partir dès la première requête.
                selectPlaylist(ref, playlist);
                // Navigate without extra (it will be picked up from provider)
                context.go('/dashboard');
              },
            );
          },
        );
      },
    );
  }
}

class _MobilePlaylistCard extends StatelessWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;

  const _MobilePlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppTheme.radiusLg));
    return DecoratedBox(
      decoration: const GlassDecoration(radius: AppTheme.radiusLg, halo: false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(AppTheme.radiusField),
                  ),
                  child: const Icon(
                    Icons.playlist_play,
                    color: AppColors.accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: AppTheme.body(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Uri.tryParse(playlist.dns)?.host ?? playlist.dns,
                        style: AppTheme.body(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
