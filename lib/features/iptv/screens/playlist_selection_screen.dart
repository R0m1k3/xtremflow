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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).currentUser;
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Select Playlist',
          style: GoogleFonts.roboto(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (currentUser?.isAdmin ?? false)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Colors.white70),
              onPressed: () => context.go('/admin'),
              tooltip: 'Admin Panel',
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
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
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              Color(0xFF2C2C2E), // Dark Grey (Apple TV Surface)
              Color(0xFF000000), // Pure Black
            ],
            stops: [0.0, 1.0],
          ),
        ),
        child: playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text('Error loading playlists', style: GoogleFonts.roboto(fontSize: 18, color: Colors.white70)),
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
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No playlists available',
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentUser?.isAdmin ?? false
                          ? 'Add playlists in Admin Panel'
                          : 'Contact administrator',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(24, 100, 24, 24), // Top padding for transparent AppBar
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
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
            color: _isHovered 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.05), // Glass effect
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered 
                  ? Colors.white.withOpacity(0.5) 
                  : Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
            boxShadow: _isHovered ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ] : [],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2), // Accent color tint
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.playlist_play,
                  size: 32,
                  color: Colors.white, // White icon
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.playlist.name,
                style: GoogleFonts.outfit( // Using Outfit for modern look
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                Uri.tryParse(widget.playlist.dns)?.host ?? widget.playlist.dns,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white54,
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

