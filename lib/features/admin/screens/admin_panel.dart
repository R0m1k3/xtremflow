import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/playlist_config.dart';

class AdminPanel extends ConsumerStatefulWidget {
  const AdminPanel({super.key});

  @override
  ConsumerState<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Playlists'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _UsersTab(),
          _PlaylistsTab(),
        ],
      ),
    );
  }
}

// ========== USERS TAB ==========
class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersBox = HiveService.usersBox;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: () => _showUserDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add User'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: usersBox.length,
            itemBuilder: (context, index) {
              final user = usersBox.getAt(index)!;
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(user.isAdmin ? Icons.admin_panel_settings : Icons.person),
                  ),
                  title: Text(user.username),
                  subtitle: Text(
                    user.isAdmin
                        ? 'Administrator'
                        : '${user.assignedPlaylistIds.length} playlist(s) assigned',
                    style: GoogleFonts.roboto(fontSize: 12),
                  ),
                  trailing: user.username == 'admin'
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteUser(context, user),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showUserDialog(BuildContext context, WidgetRef ref, [AppUser? user]) {
    final usernameController = TextEditingController(text: user?.username);
    final passwordController = TextEditingController();
    bool isAdmin = user?.isAdmin ?? false;
    List<String> selectedPlaylists = List.from(user?.assignedPlaylistIds ?? []);
    final playlistsBox = HiveService.playlistsBox;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(user == null ? 'Add User' : 'Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: user == null ? 'Password' : 'New Password (leave empty to keep)',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Administrator'),
                  value: isAdmin,
                  onChanged: (value) {
                    setState(() {
                      isAdmin = value ?? false;
                    });
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                // Playlist Assignment
                if (playlistsBox.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Assigned Playlists',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...playlistsBox.values.map((playlist) {
                    final isSelected = selectedPlaylists.contains(playlist.id);
                    return CheckboxListTile(
                      dense: true,
                      title: Text(playlist.name),
                      subtitle: Text(
                        Uri.parse(playlist.dns).host,
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selectedPlaylists.add(playlist.id);
                          } else {
                            selectedPlaylists.remove(playlist.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'No playlists available. Create playlists first.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (usernameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Username required')),
                  );
                  return;
                }

                if (user == null && passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password required')),
                  );
                  return;
                }

                final usersBox = HiveService.usersBox;
                final newUser = AppUser(
                  id: user?.id ?? const Uuid().v4(),
                  username: usernameController.text.trim(),
                  passwordHash: passwordController.text.isNotEmpty
                      ? HiveService.hashPassword(passwordController.text)
                      : user!.passwordHash,
                  isAdmin: isAdmin,
                  assignedPlaylistIds: selectedPlaylists,
                  createdAt: user?.createdAt ?? DateTime.now(),
                );

                usersBox.put(newUser.id, newUser);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteUser(BuildContext context, AppUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete user "${user.username}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              HiveService.usersBox.delete(user.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ========== PLAYLISTS TAB ==========
class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsBox = HiveService.playlistsBox;

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
          child: ListView.builder(
            itemCount: playlistsBox.length,
            itemBuilder: (context, index) {
              final playlist = playlistsBox.getAt(index)!;
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
                        onPressed: () => _deletePlaylist(context, playlist),
                      ),
                    ],
                  ),
                ),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  dnsController.text.trim().isEmpty ||
                  usernameController.text.trim().isEmpty ||
                  passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All fields required')),
                );
                return;
              }

              final playlistsBox = HiveService.playlistsBox;
              final newPlaylist = PlaylistConfig(
                id: playlist?.id ?? const Uuid().v4(),
                name: nameController.text.trim(),
                dns: dnsController.text.trim().replaceAll(RegExp(r'/$'), ''),
                username: usernameController.text.trim(),
                password: passwordController.text,
                createdAt: playlist?.createdAt ?? DateTime.now(),
              );

              playlistsBox.put(newPlaylist.id, newPlaylist);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deletePlaylist(BuildContext context, PlaylistConfig playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete playlist "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              HiveService.playlistsBox.delete(playlist.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
