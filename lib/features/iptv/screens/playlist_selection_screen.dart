import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/playlist_api_service.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/xtream_provider.dart';

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
      backgroundColor: AppColors.baseLevel0,
      appBar: AppBar(
        title: Text(
          'Select Playlist',
          style: GoogleFonts.karla(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (currentUser?.isAdmin ?? false)
            IconButton(
              icon: const Icon(
                Icons.admin_panel_settings,
                color: AppColors.textSecondary,
              ),
              onPressed: () => context.go('/admin'),
              tooltip: 'Admin Panel',
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Container(
        // `BoxConstraints.expand()` est indispensable ici : sous les
        // contraintes laches du body, ce Container se dimensionnait sur son
        // contenu (SingleChildScrollView -> Wrap shrink-wrappent tous les
        // deux), si bien que le degrade n'etait peint que sur un rectangle
        // de la taille des cartes, le reste de l'ecran restant noir.
        constraints: const BoxConstraints.expand(),
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Safety: if constraints are invalid, show loading spinner
              if (!constraints.maxWidth.isFinite ||
                  constraints.maxWidth <= 0 ||
                  !constraints.maxHeight.isFinite ||
                  constraints.maxHeight <= 0) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              return playlistsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
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
                        'Error loading playlists',
                        style: GoogleFonts.fraunces(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => ref.refresh(playlistsProvider),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                        ),
                        child: Text('Retry', style: GoogleFonts.karla()),
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
                            color: AppColors.onSurface24,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No playlists available',
                            style: GoogleFonts.fraunces(
                              fontSize: 18,
                              color: AppColors.onSurface54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentUser?.isAdmin ?? false
                                ? 'Add playlists in Admin Panel'
                                : 'Contact administrator',
                            style: GoogleFonts.karla(
                              fontSize: 14,
                              color: AppColors.onSurface38,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Simple Wrap layout - no grid, no NaN-prone calculations
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(48, 32, 48, 48),
                    child: Wrap(
                      spacing: 32,
                      runSpacing: 32,
                      children: playlists.map((playlist) {
                        return SizedBox(
                          width: 340,
                          height: 240,
                          child: _PlaylistCard(
                            playlist: playlist,
                            onTap: () {
                              ref
                                  .read(selectedPlaylistProvider.notifier)
                                  .state = playlist;
                              context.go('/dashboard');
                            },
                          ),
                        );
                      }).toList(),
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

class _PlaylistCard extends StatefulWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            // Surface OPAQUE : une plaque a 3 % de creme prenait la couleur du
            // fond et flottait sans jamais se poser dessus. Un cran de la
            // hierarchie de surfaces ancre la carte, l'ombre fait le relief.
            color: _isHovered
                ? AppColors.surfaceContainerHigh
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(
              color: _isHovered
                  ? AppColors.primaryContainer
                  : AppColors.glassLevel1Border,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow:
                _isHovered ? AppColors.emberFocus() : AppColors.lift(),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: _isHovered
                      ? AppColors.primaryGradient
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.onSurface.withOpacity(0.1),
                            AppColors.onSurface.withOpacity(0.05),
                          ],
                        ),
                  shape: BoxShape.circle,
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  Icons.playlist_play_rounded,
                  size: 32,
                  color: _isHovered ? AppColors.onSurface : AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.playlist.name,
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                Uri.tryParse(widget.playlist.dns)?.host ?? widget.playlist.dns,
                style: GoogleFonts.karla(
                  fontSize: 13,
                  color: AppColors.onSurface38,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
