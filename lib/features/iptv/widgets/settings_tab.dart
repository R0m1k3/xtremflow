import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:html' as html; // For reloading

import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/xtream_provider.dart';
import 'streaming_settings_tab.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/screens/admin_panel.dart';
import '../../../core/theme/app_theme.dart';

/// Main Settings tab with sub-tabs for Filters, Streaming, and Appearance
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _liveTvController;
  late TextEditingController _moviesController;
  late TextEditingController _seriesController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final isAdmin = ref.read(authProvider).currentUser?.isAdmin ?? false;
    _tabController = TabController(length: isAdmin ? 4 : 3, vsync: this);
    _liveTvController = TextEditingController();
    _moviesController = TextEditingController();
    _seriesController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _liveTvController.dispose();
    _moviesController.dispose();
    _seriesController.dispose();
    super.dispose();
  }

  void _syncControllers(IptvSettings settings) {
    if (!_initialized ||
        _liveTvController.text != settings.liveTvCategoryFilter) {
      _liveTvController.text = settings.liveTvCategoryFilter;
    }
    if (!_initialized ||
        _moviesController.text != settings.moviesCategoryFilter) {
      _moviesController.text = settings.moviesCategoryFilter;
    }
    if (!_initialized ||
        _seriesController.text != settings.seriesCategoryFilter) {
      _seriesController.text = settings.seriesCategoryFilter;
    }
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).currentUser;
    final settings = ref.watch(iptvSettingsProvider);

    // Sync controllers with persisted state (only on first load)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) _syncControllers(settings);
    });

    return Column(
      children: [
        // TabBar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(50),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(50),
            ),
            labelColor: AppColors.onSurface,
            unselectedLabelColor: AppColors.onSurfaceVariant,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            tabs: [
              const Tab(icon: Icon(Icons.filter_list), text: 'Filtres'),
              const Tab(icon: Icon(Icons.stream), text: 'Streaming'),
              const Tab(
                icon: Icon(Icons.smart_display_outlined),
                text: 'Lecture',
              ),
              if (currentUser?.isAdmin ?? false)
                const Tab(
                  icon: Icon(Icons.admin_panel_settings),
                  text: 'Administration',
                ),
            ],
          ),
        ),

        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Filters Tab
              _buildFiltersTab(context, currentUser, settings),

              // Streaming Tab
              const StreamingSettingsTab(),

              // Playback Tab
              _buildPlaybackTab(context, settings),

              // Admin Tab
              if (currentUser?.isAdmin ?? false) const AdminContent(),
            ],
          ),
        ),
      ],
    );
  }

  /// Lecture : réglages d'affichage du direct. (L'ancien onglet Apparence
  /// choisissait un thème clair ou sombre ; la charte n'a qu'un mode sombre.)
  Widget _buildPlaybackTab(BuildContext context, IptvSettings settings) {
    final notifier = ref.read(iptvSettingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SwitchListTile(
            value: settings.livePreview,
            onChanged: notifier.setLivePreview,
            secondary: const Icon(
              Icons.smart_display_outlined,
              color: AppColors.accent,
            ),
            title: Text(
              'Aperçu vidéo dans le Direct',
              style: AppTheme.body(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              "Image muette de la chaîne survolée, dans le panneau de droite. "
              "Elle utilise une connexion de l'abonnement, rendue dès qu'on "
              'quitte la liste ou qu\'on ouvre le plein écran.',
              style: AppTheme.body(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersTab(
    BuildContext context,
    dynamic currentUser,
    IptvSettings settings,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User info card
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          padding: const EdgeInsets.all(4),
          child: ListTile(
            leading: const Icon(Icons.person, color: AppColors.onSurface),
            title: Text(
              'Connecté en tant que',
              style: AppTheme.font(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            subtitle: Text(
              currentUser?.username ?? 'Unknown',
              style: AppTheme.font(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            trailing: currentUser?.isAdmin ?? false
                ? Chip(
                    label: Text(
                      'Admin',
                      style: AppTheme.font(
                        fontSize: 11,
                        color: AppColors.onPrimaryContainer,
                      ),
                    ),
                    backgroundColor: AppColors.onSurface,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Category filters section
        Text(
          'Filtres de Catégories',
          style: AppTheme.font(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Seules les catégories contenant un de ces mots-clés seront affichées. Séparez par des virgules.',
          style: AppTheme.font(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),

        // Live TV Filter
        _buildFilterCard(
          title: 'Filtre TV Live',
          icon: Icons.live_tv,
          controller: _liveTvController,
          keywords: settings.liveTvKeywords,
          onChanged: (value) {
            ref.read(iptvSettingsProvider.notifier).setLiveTvFilter(value);
          },
          onClear: () {
            _liveTvController.clear();
            ref.read(iptvSettingsProvider.notifier).clearLiveTvFilter();
          },
        ),
        const SizedBox(height: 8),

        // Movies Filter
        _buildFilterCard(
          title: 'Filtre Films',
          icon: Icons.movie,
          controller: _moviesController,
          keywords: settings.moviesKeywords,
          onChanged: (value) {
            ref.read(iptvSettingsProvider.notifier).setMoviesFilter(value);
          },
          onClear: () {
            _moviesController.clear();
            ref.read(iptvSettingsProvider.notifier).clearMoviesFilter();
          },
        ),
        const SizedBox(height: 8),

        // Series Filter
        _buildFilterCard(
          title: 'Filtre Séries',
          icon: Icons.tv,
          controller: _seriesController,
          keywords: settings.seriesKeywords,
          onChanged: (value) {
            ref.read(iptvSettingsProvider.notifier).setSeriesFilter(value);
          },
          onClear: () {
            _seriesController.clear();
            ref.read(iptvSettingsProvider.notifier).clearSeriesFilter();
          },
        ),
        const SizedBox(height: 16),

        // Change playlist
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: ListTile(
            leading: const Icon(
              Icons.playlist_play,
              color: AppColors.onSurface,
            ),
            title: Text(
              'Changer de Playlist',
              style: AppTheme.font(color: AppColors.onSurface),
            ),
            // L'IPTV active, pour savoir d'où viennent guide, enregistrements
            // et Auto NBA avant d'en changer.
            subtitle: Text(
              ref.watch(selectedPlaylistProvider)?.name ?? 'Aucune',
              overflow: TextOverflow.ellipsis,
              style: AppTheme.font(color: AppColors.textTertiary, fontSize: 11),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.onSurfaceVariant,
            ),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 8),

        // About
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.onSurface),
            title: Text(
              'À propos',
              style: AppTheme.font(color: AppColors.onSurface),
            ),
            subtitle: Text(
              'XtremFlow IPTV v1.0.0',
              style: AppTheme.font(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Maintenance Section
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: ListTile(
            leading: const Icon(
              Icons.cleaning_services,
              color: AppColors.warning,
            ),
            title: Text(
              'Maintenance',
              style: AppTheme.font(color: AppColors.onSurface),
            ),
            subtitle: Text(
              'En cas de problèmes d\'affichage ou de mise à jour',
              style: AppTheme.font(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            trailing: FilledButton.icon(
              onPressed: () {
                // Show confirmation dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.surfaceContainer,
                    title: const Text(
                      'Vider le cache ?',
                      style: TextStyle(color: AppColors.onSurface),
                    ),
                    content: const Text(
                      'Cette action va recharger l\'application et effacer les données temporaires.\n'
                      'Vos réglages et favoris sont sauvegardés sur le serveur.',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                        ),
                        onPressed: () {
                          Navigator.pop(context);

                          // Clear Flutter Image Cache
                          PaintingBinding.instance.imageCache.clear();
                          PaintingBinding.instance.imageCache.clearLiveImages();

                          // Clear Browser Local Storage (SharedPreferences backend for Web)
                          html.window.localStorage.clear();
                          html.window.sessionStorage.clear();

                          // Reload application
                          html.window.location.reload();
                        },
                        child: const Text('Vider et Recharger'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Vider le Cache'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning.withOpacity(0.2),
                foregroundColor: AppColors.warning,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Logout button
        FilledButton.icon(
          onPressed: () {
            ref.read(authProvider.notifier).logout();
            context.go('/login');
          },
          icon: const Icon(Icons.logout),
          label: const Text('Déconnexion'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterCard({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required List<String> keywords,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryContainer),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.font(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Ex: FR,FRANCE,HD,SPORT',
              hintStyle: AppTheme.font(fontSize: 12, color: AppColors.outline),
              filled: true,
              fillColor: AppColors.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: AppColors.onSurfaceVariant,
                      ),
                      onPressed: onClear,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : null,
            ),
            style: AppTheme.font(fontSize: 12, color: AppColors.onSurface),
            onChanged: onChanged,
          ),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: AppColors.primaryContainer.withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    keyword,
                    style: AppTheme.font(
                      fontSize: 11,
                      color: AppColors.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
