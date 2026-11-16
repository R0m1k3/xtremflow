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
import '../../../core/theme/glass.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tv_focusable.dart';

/// Users provider for admin panel
final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  final service = UserApiService();
  return service.getAllUsers();
});

class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      body: AmbientBackground(child: AdminContent()),
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
                  child: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 16),
                Text('Administration', style: AppTheme.display(fontSize: 26)),
                const Spacer(),
                // Custom Tab Bar Indicator
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const GlassDecoration(radius: 999, halo: false),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabButton(0, 'Playlists', Icons.playlist_play),
                      const SizedBox(width: 4),
                      _buildTabButton(1, 'Utilisateurs', Icons.people_outline),
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
              children: const [_PlaylistsTab(), _UsersTab()],
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
        return TVFocusable(
          paintsOwnFocus: true,
          scale: 1.0,
          borderRadius: BorderRadius.circular(999),
          onPressed: () => _tabController.animateTo(index),
          child: Builder(
            builder: (context) {
              final lit = TVFocusable.isFocused(context);
              final ink = lit
                  ? AppColors.onFocus
                  : (isSelected ? AppColors.accent : AppColors.textMuted);
              return AnimatedContainer(
                duration: AppTheme.durationFocus,
                curve: AppTheme.curveFocus,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: lit
                      ? AppColors.focus
                      : (isSelected
                            ? AppColors.accentFill
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: ink),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: AppTheme.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              );
            },
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
              Text(
                '${playlistsAsync.asData?.value.length ?? 0} playlists',
                style: AppTheme.body(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
              GradientButton(
                label: 'Ajouter une playlist',
                icon: Icons.add,
                onPressed: () => _showPlaylistDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlistsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
            error: (error, stack) => Center(
              child: Text(
                'Erreur : $error',
                style: AppTheme.body(fontSize: 15, color: AppColors.error),
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
                        'Aucune playlist configurée',
                        style: AppTheme.body(
                          fontSize: 17,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _showPlaylistDialog(context, ref),
                        child: const Text('Ajouter votre première playlist'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
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
                            color: AppColors.accentFill,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.playlist_play,
                            color: AppColors.accent,
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
                              ),
                              const SizedBox(height: 4),
                              Text(
                                playlist.dns,
                                style: AppTheme.body(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: AppColors.textSecondary,
                              onPressed: () =>
                                  _showPlaylistDialog(context, ref, playlist),
                              tooltip: 'Modifier',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: AppColors.error,
                              onPressed: () =>
                                  _deletePlaylist(context, ref, playlist),
                              tooltip: 'Supprimer',
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

  void _showPlaylistDialog(
    BuildContext context,
    WidgetRef ref, [
    PlaylistConfig? playlist,
  ]) {
    final nameController = TextEditingController(text: playlist?.name);
    final dnsController = TextEditingController(text: playlist?.dns);
    final usernameController = TextEditingController(text: playlist?.username);
    final passwordController = TextEditingController(text: playlist?.password);
    final service = PlaylistApiService();
    bool isLoading = false;

    showAppDialog(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: playlist == null
              ? 'Ajouter une playlist'
              : 'Modifier la playlist',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(controller: nameController, label: 'Nom', autofocus: true),
              const SizedBox(height: 12),
              _field(
                controller: dnsController,
                label: 'URL du serveur',
                hint: 'http://server.com:8080',
              ),
              const SizedBox(height: 12),
              _field(controller: usernameController, label: 'Utilisateur'),
              const SizedBox(height: 12),
              _field(
                controller: passwordController,
                label: 'Mot de passe',
                obscure: true,
              ),
            ],
          ),
          actions: [
            AppDialogButton(
              label: 'Annuler',
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
            ),
            AppDialogButton(
              label: isLoading ? 'Enregistrement…' : 'Sauvegarder',
              primary: true,
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameController.text.isEmpty ||
                          dnsController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tous les champs sont requis'),
                          ),
                        );
                        return;
                      }
                      setState(() => isLoading = true);
                      final dns = dnsController.text.trim().replaceAll(
                        RegExp(r'/$'),
                        '',
                      );
                      if (playlist == null) {
                        await service.createPlaylist(
                          name: nameController.text.trim(),
                          dns: dns,
                          username: usernameController.text.trim(),
                          password: passwordController.text,
                        );
                      } else {
                        await service.updatePlaylist(
                          id: playlist.id,
                          name: nameController.text.trim(),
                          dns: dns,
                          username: usernameController.text.trim(),
                          password: passwordController.text,
                        );
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      ref.invalidate(playlistsProvider);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    PlaylistConfig playlist,
  ) async {
    final ok = await showAppConfirm(
      context,
      title: 'Supprimer la playlist',
      message: 'Supprimer « ${playlist.name} » ?',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    await PlaylistApiService().deletePlaylist(playlist.id);
    ref.invalidate(playlistsProvider);
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
              Text(
                '${usersAsync.asData?.value.length ?? 0} utilisateurs',
                style: AppTheme.body(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
              GradientButton(
                label: 'Créer un utilisateur',
                icon: Icons.person_add,
                onPressed: () => _showCreateUserDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
            error: (error, stack) => Center(
              child: Text(
                'Erreur : $error',
                style: AppTheme.body(fontSize: 15, color: AppColors.error),
              ),
            ),
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.people_outline,
                        size: 64,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun utilisateur',
                        style: AppTheme.body(
                          fontSize: 17,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
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
                            color: user.isAdmin
                                ? AppColors.accentFill
                                : AppColors.surfaceHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            user.isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: user.isAdmin
                                ? AppColors.accent
                                : AppColors.textSecondary,
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
                                  Text(
                                    user.username,
                                    style: AppTheme.body(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (user.isAdmin) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentFill,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'Admin',
                                        style: AppTheme.body(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID : ${user.id}',
                                style: AppTheme.body(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Actions',
                          icon: const Icon(
                            Icons.more_vert,
                            color: AppColors.textSecondary,
                          ),
                          color: AppColors.surfaceHigh,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.hairline),
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'password':
                                _showChangePasswordDialog(context, ref, user);
                                break;
                              case 'delete':
                                _deleteUser(context, ref, user);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'password',
                              child: Row(
                                children: [
                                  Icon(Icons.lock_reset, size: 18),
                                  SizedBox(width: 8),
                                  Text('Changer le mot de passe'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Supprimer',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ],
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
      ],
    );
  }

  void _showCreateUserDialog(BuildContext context, WidgetRef ref) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isAdmin = false;
    bool isLoading = false;

    showAppDialog(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: 'Créer un utilisateur',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(
                controller: usernameController,
                label: "Nom d'utilisateur",
                icon: Icons.person_outline,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _field(
                controller: passwordController,
                label: 'Mot de passe',
                icon: Icons.lock_outline,
                obscure: true,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Administrateur',
                  style: AppTheme.body(fontSize: 15),
                ),
                subtitle: Text(
                  "Accès à l'administration",
                  style: AppTheme.body(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                value: isAdmin,
                onChanged: (v) => setState(() => isAdmin = v),
              ),
            ],
          ),
          actions: [
            AppDialogButton(
              label: 'Annuler',
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
            ),
            AppDialogButton(
              label: isLoading ? 'Création…' : 'Créer',
              primary: true,
              onPressed: isLoading
                  ? null
                  : () async {
                      if (usernameController.text.isEmpty ||
                          passwordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tous les champs sont requis'),
                          ),
                        );
                        return;
                      }
                      setState(() => isLoading = true);
                      final result = await UserApiService().createUser(
                        username: usernameController.text.trim(),
                        password: passwordController.text,
                        isAdmin: isAdmin,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      ref.invalidate(usersProvider);
                      if (!result.success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? 'Erreur'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) {
    final passwordController = TextEditingController();
    bool isLoading = false;

    showAppDialog(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: 'Changer le mot de passe de ${user.username}',
          content: _field(
            controller: passwordController,
            label: 'Nouveau mot de passe',
            icon: Icons.lock_outline,
            obscure: true,
            autofocus: true,
          ),
          actions: [
            AppDialogButton(
              label: 'Annuler',
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
            ),
            AppDialogButton(
              label: isLoading ? 'Modification…' : 'Changer',
              primary: true,
              onPressed: isLoading
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mot de passe requis')),
                        );
                        return;
                      }
                      setState(() => isLoading = true);
                      final result = await UserApiService().updatePassword(
                        userId: user.id,
                        newPassword: passwordController.text,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (result.success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mot de passe modifié'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? 'Erreur'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final ok = await showAppConfirm(
      context,
      title: "Supprimer l'utilisateur",
      message:
          'Supprimer « ${user.username} » ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok) return;
    final result = await UserApiService().deleteUser(user.id);
    ref.invalidate(usersProvider);
    if (!result.success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Erreur'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Text field of the admin dialogs: the theme field, sunk (rail) and with
/// an accent edge when focused.
Widget _field({
  required TextEditingController controller,
  required String label,
  String? hint,
  IconData? icon,
  bool obscure = false,
  bool autofocus = false,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    autofocus: autofocus,
    cursorColor: AppColors.accent,
    style: AppTheme.body(fontSize: 16),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
      floatingLabelStyle: AppTheme.body(fontSize: 15, color: AppColors.accent),
      prefixIcon: icon == null ? null : Icon(icon, color: AppColors.textMuted),
      fillColor: AppColors.rail,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
  );
}
