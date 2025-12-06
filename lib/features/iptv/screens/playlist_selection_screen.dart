import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/playlist_api_service.dart';
import '../../../core/models/playlist_config.dart';
import '../../auth/providers/auth_provider.dart';

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
      appBar: AppBar(
        title: Text(
          'Select Playlist',
          style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (currentUser?.isAdmin ?? false)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => context.go('/admin'),
              tooltip: 'Admin Panel',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
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
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text('Error loading playlists', style: GoogleFonts.roboto(fontSize: 18)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.refresh(playlistsProvider),
                child: const Text('Retry'),
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
                  Icon(
                    Icons.playlist_remove,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No playlists available',
                    style: GoogleFonts.roboto(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentUser?.isAdmin ?? false
                        ? 'Add playlists in Admin Panel'
                        : 'Contact administrator',
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _PlaylistCard(
                playlist: playlist,
                onTap: () {
                  context.go('/dashboard', extra: playlist);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade700,
                Colors.blue.shade900,
              ],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.playlist_play,
                size: 48,
                color: Colors.white.withOpacity(0.9),
              ),
              const SizedBox(height: 12),
              Text(
                playlist.name,
                style: GoogleFonts.roboto(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                Uri.tryParse(playlist.dns)?.host ?? playlist.dns,
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.7),
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
