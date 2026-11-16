import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:html' as html; // For reloading

import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/xtream_provider.dart';
import 'streaming_settings_tab.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/screens/admin_panel.dart';
import '../../../core/theme/app_theme.dart';

/// Réglages : onglets Filtres, Streaming, Lecture (et Administration).
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const GlassDecoration(radius: 999, halo: false),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.accentFill,
                borderRadius: BorderRadius.circular(999),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: AppTheme.body(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              unselectedLabelStyle: AppTheme.body(fontSize: 14),
              dividerColor: Colors.transparent,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              tabs: [
                const Tab(
                  height: 44,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.filter_list, size: 20),
                  text: 'Filtres',
                ),
                const Tab(
                  height: 44,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.stream, size: 20),
                  text: 'Streaming',
                ),
                const Tab(
                  height: 44,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.smart_display_outlined, size: 20),
                  text: 'Lecture',
                ),
                if (currentUser?.isAdmin ?? false)
                  const Tab(
                    height: 44,
                    iconMargin: EdgeInsets.only(bottom: 2),
                    icon: Icon(Icons.admin_panel_settings_outlined, size: 20),
                    text: 'Administration',
                  ),
              ],
            ),
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
        GlassContainer(
          padding: const EdgeInsets.all(4),
          child: ListTile(
            leading: const Icon(Icons.person_outline, color: AppColors.accent),
            title: Text(
              'Connecté en tant que',
              style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
            ),
            subtitle: Text(
              currentUser?.username ?? 'Inconnu',
              style: AppTheme.body(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: currentUser?.isAdmin ?? false
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentFill,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Admin',
                      style: AppTheme.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 24),

        // Category filters section
        Text('Filtres de catégories', style: AppTheme.display(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Seules les catégories contenant un de ces mots-clés seront affichées. Séparez par des virgules.',
          style: AppTheme.body(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        // Live TV Filter
        _buildFilterCard(
          title: 'Filtre Direct',
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
        const SizedBox(height: 10),

        // Movies Filter
        _buildFilterCard(
          title: 'Filtre Films',
          icon: Icons.movie_outlined,
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
        const SizedBox(height: 10),

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
        const SizedBox(height: 24),

        // Change playlist
        GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.playlist_play, color: AppColors.accent),
            title: Text(
              'Changer de playlist',
              style: AppTheme.body(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            // L'IPTV active, pour savoir d'où viennent guide, enregistrements
            // et Auto NBA avant d'en changer.
            subtitle: Text(
              ref.watch(selectedPlaylistProvider)?.name ?? 'Aucune',
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
            ),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 10),

        // About
        GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.accent),
            title: Text(
              'À propos',
              style: AppTheme.body(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'XtremFlow IPTV v1.0.0',
              style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Maintenance Section
        GlassContainer(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(
              Icons.cleaning_services_outlined,
              color: AppColors.accent,
            ),
            title: Text(
              'Maintenance',
              style: AppTheme.body(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'En cas de problèmes d\'affichage ou de mise à jour',
              style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
            ),
            trailing: OutlinedButton.icon(
              onPressed: () async {
                // Show confirmation dialog
                final ok = await showAppConfirm(
                  context,
                  title: 'Vider le cache ?',
                  message:
                      'Cette action va recharger l\'application et effacer les données temporaires.\n'
                      'Vos réglages et favoris sont sauvegardés sur le serveur.',
                  confirmLabel: 'Vider et recharger',
                );
                if (!ok) return;

                // Clear Flutter Image Cache
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();

                // Clear Browser Local Storage (SharedPreferences backend for Web)
                html.window.localStorage.clear();
                html.window.sessionStorage.clear();

                // Reload application
                html.window.location.reload();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Vider le cache'),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Logout button
        OutlinedButton.icon(
          onPressed: () {
            ref.read(authProvider.notifier).logout();
            context.go('/login');
          },
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.track),
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
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.body(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: 'Ex : FR,FRANCE,HD,SPORT',
              fillColor: AppColors.rail,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusField),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onPressed: onClear,
                    )
                  : null,
            ),
            style: AppTheme.body(fontSize: 14),
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
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    keyword,
                    style: AppTheme.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
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
