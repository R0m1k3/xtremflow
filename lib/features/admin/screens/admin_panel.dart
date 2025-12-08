import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
        child: const AdminContent(),
      ),
    );
  }
}

class AdminContent extends ConsumerStatefulWidget {
  const AdminContent({super.key});

  @override
  ConsumerState<AdminContent> createState() => _AdminContentState();
}

class _AdminContentState extends ConsumerState<AdminContent>
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
    return SafeArea(
      child: Column(
        children: [
          // Custom Glass Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // Back button only if standalone (optional, keeping for now)
                GlassCard(
                  borderRadius: 12,
                  padding: const EdgeInsets.all(8),
                  showBorder: false,
                  onTap: () => context.go('/playlists'),
                  child: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
                const SizedBox(width: 16),
                Text(
                  'Administration',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Custom Tab Bar Indicator
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabButton(0, 'Playlists', Icons.playlist_play),
                      const SizedBox(width: 4),
                      _buildTabButton(1, 'Users', Icons.people),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(), // Custom tabs handle ref
              children: const [
                _PlaylistsTab(),
                _UsersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, child) {
        final isSelected = _tabController.index == index;
        return GestureDetector(
          onTap: () => _tabController.animateTo(index),
          child: AnimatedContainer(
            duration: AppTheme.durationFast,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.focusColor : Colors.transparent,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.black : Colors.white70,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${playlistsAsync.asData?.value.length ?? 0} Playlists', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70)),
              GradientButton(
                label: 'Add Playlist',
                icon: Icons.add,
                onPressed: () => _showPlaylistDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error', style: const TextStyle(color: AppColors.error))),
            data: (playlists) {
              if (playlists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.playlist_remove, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No playlists configured', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _showPlaylistDialog(context, ref),
                        child: const Text('Add your first playlist'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: playlists.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.playlist_play, color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(playlist.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(playlist.dns, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: Colors.white70,
                              onPressed: () => _showPlaylistDialog(context, ref, playlist),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: AppColors.error,
                              onPressed: () => _deletePlaylist(context, ref, playlist),
                              tooltip: 'Delete',
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text('${usersAsync.asData?.value.length ?? 0} Users', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70)),
              GradientButton(
                label: 'Create User',
                icon: Icons.person_add,
                onPressed: () => _showCreateUserDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error', style: const TextStyle(color: AppColors.error))),
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No users found', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: user.isAdmin ? AppColors.focusColor : AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                            color: user.isAdmin ? Colors.black : AppColors.textPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(user.username, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                                  if (user.isAdmin) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.focusColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.focusColor)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('ID: ${user.id}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60)),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white70),
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            switch (value) {
                              case 'password': _showChangePasswordDialog(context, ref, user); break;
                              case 'delete': _deleteUser(context, ref, user); break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'password', child: Row(children: [Icon(Icons.lock_reset, size: 18), SizedBox(width: 8), Text('Change Password')])),
                            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: AppColors.error, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.error))])),
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
