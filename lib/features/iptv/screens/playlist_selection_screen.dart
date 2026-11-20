import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/playlist_api_service.dart';
import '../../../core/api/authed_http.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/xtream_provider.dart';
import '../../../core/theme/glass.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../../../core/widgets/xtremflow_mark.dart';

/// Provider for fetching playlists from API
final playlistsProvider = FutureProvider<List<PlaylistConfig>>((ref) async {
  final service = PlaylistApiService();
  return service.getPlaylists();
});

class PlaylistSelectionScreen extends ConsumerWidget {
  const PlaylistSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).currentUser;
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      // Filet de securite : meme pendant une transition de route, le fond
      // reste dans la palette au lieu de virer au noir pur.
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 32,
        title: const XtremFlowWordmark(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (currentUser?.isAdmin ?? false)
            TextButton.icon(
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
              label: const Text('Administration'),
              onPressed: () => context.go('/admin'),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('Se déconnecter'),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          const SizedBox(width: 24),
        ],
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Safety: if constraints are invalid, show loading spinner
              if (!constraints.maxWidth.isFinite ||
                  constraints.maxWidth <= 0 ||
                  !constraints.maxHeight.isFinite ||
                  constraints.maxHeight <= 0) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }

              return playlistsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Impossible de charger les playlists',
                        style: AppTheme.body(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
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
                            size: 64,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucune playlist disponible',
                            style: AppTheme.body(
                              fontSize: 18,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentUser?.isAdmin ?? false
                                ? "Ajoutez-en dans l'administration"
                                : "Contactez l'administrateur",
                            style: AppTheme.body(
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Simple Wrap layout - no grid, no NaN-prone calculations
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(48, 24, 48, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choisir une IPTV',
                          style: AppTheme.display(fontSize: 30),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Guide, enregistrements et favoris suivent '
                          "l'IPTV choisie.",
                          style: AppTheme.body(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          children: [
                            for (var i = 0; i < playlists.length; i++)
                              SizedBox(
                                width: 340,
                                height: 220,
                                child: _PlaylistCard(
                                  playlist: playlists[i],
                                  autofocus: i == 0,
                                  onTap: () {
                                    final playlist = playlists[i];
                                    AuthedHttp.usePlaylist(
                                      playlist.id,
                                      json: playlist.toJson(),
                                    );
                                    selectPlaylist(ref, playlist);
                                    context.go('/dashboard');
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A playlist: resting glass, the lit card on focus (hover on the web).
class _PlaylistCard extends StatelessWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;
  final bool autofocus;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      scale: 1.03,
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      onPressed: onTap,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            decoration: GlassDecoration(
              lit: lit ? 1 : 0,
              radius: AppTheme.radiusXl,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: AppTheme.durationFocus,
                  curve: AppTheme.curveFocus,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: lit ? AppColors.onFocus : AppColors.accentFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.playlist_play_rounded,
                    size: 30,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  playlist.name,
                  style: AppTheme.display(
                    fontSize: 22,
                    height: 1.2,
                    color: lit ? AppColors.onFocus : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  Uri.tryParse(playlist.dns)?.host ?? playlist.dns,
                  style: AppTheme.body(
                    fontSize: 14,
                    color: lit ? AppColors.onFocusMuted : AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
