import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/playlist_api_service.dart';
import '../../../core/services/user_api_service.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/app_user.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/components/ui_components.dart';
import '../../iptv/screens/playlist_selection_screen.dart';

/// Users provider for admin panel
final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  final service = UserApiService();
  return service.getAllUsers();
});

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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Administration'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/playlists'),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.playlist_play), text: 'Playlists'),
            Tab(icon: Icon(Icons.people), text: 'Utilisateurs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _PlaylistsTab(),
          _UsersTab(),
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
    final playlistsAsync = ref.watch(playlistsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: GradientButton(
            label: 'Ajouter une playlist',
            icon: Icons.add,
            onPressed: () => _showPlaylistDialog(context, ref),
          ),
        ),
        Expanded(
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text('Erreur: $error'),
                  const SizedBox(height: 8),
                  OutlinedButton(
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
                      Icon(Icons.playlist_remove, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune playlist',
                        style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.playlist_play, color: Colors.black, size: 20),
                      ),
                      title: Text(playlist.name),
                      subtitle: Text(playlist.dns, style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showPlaylistDialog(context, ref, playlist),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: AppColors.error),
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
          title: Text(playlist == null ? 'Ajouter une playlist' : 'Modifier la playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
                const SizedBox(height: 12),
                TextField(controller: dnsController, decoration: const InputDecoration(labelText: 'URL du serveur', hintText: 'http://server.com:8080')),
                const SizedBox(height: 12),
                TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'Utilisateur')),
                const SizedBox(height: 12),
                TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Mot de passe'), obscureText: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: isLoading ? null : () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: isLoading ? null : () async {
                if (nameController.text.isEmpty || dnsController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les champs sont requis')));
                  return;
                }
                setState(() => isLoading = true);
                final dns = dnsController.text.trim().replaceAll(RegExp(r'/$'), '');
                if (playlist == null) {
                  await service.createPlaylist(name: nameController.text.trim(), dns: dns, username: usernameController.text.trim(), password: passwordController.text);
                } else {
                  await service.updatePlaylist(id: playlist.id, name: nameController.text.trim(), dns: dns, username: usernameController.text.trim(), password: passwordController.text);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ref.invalidate(playlistsProvider);
              },
              child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sauvegarder'),
            ),
          ],
        ),
      ),
    );
  }

  void _deletePlaylist(BuildContext context, WidgetRef ref, PlaylistConfig playlist) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer la playlist'),
        content: Text('Supprimer "${playlist.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PlaylistApiService().deletePlaylist(playlist.id);
              ref.invalidate(playlistsProvider);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
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
    final usersAsync = ref.watch(usersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: GradientButton(
            label: 'Créer un utilisateur',
            icon: Icons.person_add,
            onPressed: () => _showCreateUserDialog(context, ref),
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text('Erreur: $error'),
                  OutlinedButton(
                    onPressed: () => ref.refresh(usersProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text('Aucun utilisateur', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: user.isAdmin ? AppColors.primary.withOpacity(0.2) : AppColors.surface.withOpacity(0.5),
                        child: Icon(user.isAdmin ? Icons.admin_panel_settings : Icons.person, color: user.isAdmin ? AppColors.primary : AppColors.textSecondary),
                      ),
                      title: Row(
                        children: [
                          Text(user.username),
                          if (user.isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                              child: Text('Admin', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text('ID: ${user.id}', style: const TextStyle(fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'password': _showChangePasswordDialog(context, ref, user); break;
                            case 'delete': _deleteUser(context, ref, user); break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'password', child: ListTile(leading: Icon(Icons.lock_reset), title: Text('Changer mot de passe'), dense: true)),
                          PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: AppColors.error), title: Text('Supprimer', style: TextStyle(color: AppColors.error)), dense: true)),
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

  void _showCreateUserDialog(BuildContext context, WidgetRef ref) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isAdmin = false;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Créer un utilisateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'Nom d\'utilisateur', prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 12),
              TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)), obscureText: true),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Administrateur'),
                subtitle: const Text('Accès au panneau admin'),
                value: isAdmin,
                onChanged: (v) => setState(() => isAdmin = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: isLoading ? null : () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: isLoading ? null : () async {
                if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les champs sont requis')));
                  return;
                }
                setState(() => isLoading = true);
                final result = await UserApiService().createUser(username: usernameController.text.trim(), password: passwordController.text, isAdmin: isAdmin);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ref.invalidate(usersProvider);
                if (!result.success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Erreur'), backgroundColor: AppColors.error));
                }
              },
              child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref, AppUser user) {
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Changer le mot de passe de ${user.username}'),
          content: TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Nouveau mot de passe', prefixIcon: Icon(Icons.lock_outline)), obscureText: true),
          actions: [
            TextButton(onPressed: isLoading ? null : () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: isLoading ? null : () async {
                if (passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe requis')));
                  return;
                }
                setState(() => isLoading = true);
                final result = await UserApiService().updatePassword(userId: user.id, newPassword: passwordController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (result.success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mot de passe modifié'), backgroundColor: AppColors.success));
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Erreur'), backgroundColor: AppColors.error));
                }
              },
              child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Changer'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteUser(BuildContext context, WidgetRef ref, AppUser user) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer l\'utilisateur'),
        content: Text('Supprimer "${user.username}" ? Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final result = await UserApiService().deleteUser(user.id);
              ref.invalidate(usersProvider);
              if (!result.success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Erreur'), backgroundColor: AppColors.error));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
