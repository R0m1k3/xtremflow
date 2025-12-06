import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/playlist_api_service.dart';
import '../../../core/models/playlist_config.dart';
import '../../iptv/screens/playlist_selection_screen.dart';

class AdminPanel extends ConsumerStatefulWidget {
  const AdminPanel({super.key});

  @override
  ConsumerState<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanel> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Panel',
          style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/playlists'),
        ),
      ),
      body: const _PlaylistsTab(),
    );
  }
}

// ========== PLAYLISTS TAB ==========
class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: () => _showPlaylistDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Playlist'),
          ),
        ),
        Expanded(
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text('Error loading playlists: $error'),
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
                      Icon(Icons.playlist_remove, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No playlists yet',
                        style: GoogleFonts.roboto(fontSize: 18, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click "Add Playlist" to create one',
                        style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.playlist_play),
                      ),
                      title: Text(playlist.name),
                      subtitle: Text(
                        playlist.dns,
                        style: GoogleFonts.roboto(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showPlaylistDialog(context, ref, playlist),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deletePlaylist(context, ref, playlist),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPlaylistDialog(BuildContext context, WidgetRef ref, [PlaylistConfig? playlist]) {
    final nameController = TextEditingController(text: playlist?.name);
    final dnsController = TextEditingController(text: playlist?.dns);
    final usernameController = TextEditingController(text: playlist?.username);
    final passwordController = TextEditingController(text: playlist?.password);
    final service = PlaylistApiService();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(playlist == null ? 'Add Playlist' : 'Edit Playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Playlist Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dnsController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://server.com:8080',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty ||
                          dnsController.text.trim().isEmpty ||
                          usernameController.text.trim().isEmpty ||
                          passwordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All fields required')),
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      final dns = dnsController.text.trim().replaceAll(RegExp(r'/$'), '');

                      PlaylistConfig? result;
                      if (playlist == null) {
                        // Create new playlist
                        result = await service.createPlaylist(
                          name: nameController.text.trim(),
                          dns: dns,
                          username: usernameController.text.trim(),
                          password: passwordController.text,
                        );
                      } else {
                        // Update existing playlist
                        result = await service.updatePlaylist(
                          id: playlist.id,
                          name: nameController.text.trim(),
                          dns: dns,
                          username: usernameController.text.trim(),
                          password: passwordController.text,
                        );
                      }

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }

                      // Refresh playlists list
                      ref.invalidate(playlistsProvider);

                      if (result == null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to save playlist'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deletePlaylist(BuildContext context, WidgetRef ref, PlaylistConfig playlist) {
    final service = PlaylistApiService();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete playlist "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              final success = await service.deletePlaylist(playlist.id);
              
              // Refresh playlists list
              ref.invalidate(playlistsProvider);
              
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to delete playlist'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
