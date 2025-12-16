import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html; // For reloading
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'streaming_settings_tab.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/screens/admin_panel.dart';

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
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(50),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            tabs: [
              const Tab(icon: Icon(Icons.filter_list), text: 'Filtres'),
              const Tab(icon: Icon(Icons.stream), text: 'Streaming'),
              const Tab(icon: Icon(Icons.palette), text: 'Apparence'),
              if (currentUser?.isAdmin ?? false)
                const Tab(
                    icon: Icon(Icons.admin_panel_settings),
                    text: 'Administration'),
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

              // Appearance Tab
              _buildAppearanceTab(context),

              // Admin Tab
              if (currentUser?.isAdmin ?? false) const AdminContent(),
            ],
          ),
        ),
      ],
    );
  }

  /// Build Appearance tab with theme toggle
  Widget _buildAppearanceTab(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Theme selection card
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.dark_mode,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Thème',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Theme options
              _buildThemeOption(
                context: context,
                title: 'Système',
                subtitle: 'Suivre les paramètres du système',
                icon: Icons.settings_suggest,
                isSelected: themeState.appThemeMode == AppThemeMode.system,
                onTap: () => themeNotifier.setThemeMode(AppThemeMode.system),
              ),
              const SizedBox(height: 8),
              _buildThemeOption(
                context: context,
                title: 'Sombre',
                subtitle: 'Interface sombre premium',
                icon: Icons.dark_mode,
                isSelected: themeState.appThemeMode == AppThemeMode.dark,
                onTap: () => themeNotifier.setThemeMode(AppThemeMode.dark),
              ),
              const SizedBox(height: 8),
              _buildThemeOption(
                context: context,
                title: 'Clair',
                subtitle: 'Interface claire et lumineuse',
                icon: Icons.light_mode,
                isSelected: themeState.appThemeMode == AppThemeMode.light,
                onTap: () => themeNotifier.setThemeMode(AppThemeMode.light),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick toggle card
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: Colors.white,
            ),
            title: Text(
              'Mode actuel',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500, color: Colors.white),
            ),
            subtitle: Text(
              isDark ? 'Thème sombre actif' : 'Thème clair actif',
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Switch(
              value: isDark,
              onChanged: (_) => themeNotifier.toggleTheme(),
              activeThumbColor: AppColors.primary,
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary.withOpacity(0.5)
                    : Colors.grey.shade800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.1)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersTab(
      BuildContext context, dynamic currentUser, IptvSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User info card
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.all(4),
          child: ListTile(
            leading: const Icon(Icons.person, color: Colors.white),
            title: Text(
              'Connecté en tant que',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.white70),
            ),
            subtitle: Text(
              currentUser?.username ?? 'Unknown',
              style: GoogleFonts.roboto(
                  fontWeight: FontWeight.w600, color: Colors.white),
            ),
            trailing: currentUser?.isAdmin ?? false
                ? Chip(
                    label: Text('Admin',
                        style: GoogleFonts.roboto(
                            fontSize: 11, color: Colors.black)),
                    backgroundColor: Colors.white,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Category filters section
        Text(
          'Filtres de Catégories',
          style: GoogleFonts.roboto(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Seules les catégories contenant un de ces mots-clés seront affichées. Séparez par des virgules.',
          style: GoogleFonts.roboto(
            fontSize: 12,
            color: Colors.white54,
          ),
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
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            leading: const Icon(Icons.playlist_play, color: Colors.white),
            title: Text('Changer de Playlist',
                style: GoogleFonts.roboto(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 8),

        // About
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: Text('À propos',
                style: GoogleFonts.roboto(color: Colors.white)),
            subtitle: Text(
              'XtremFlow IPTV v1.0.0',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.white54),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Maintenance Section
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: ListTile(
            leading: const Icon(Icons.cleaning_services, color: Colors.orange),
            title: Text('Maintenance',
                style: GoogleFonts.roboto(color: Colors.white)),
            subtitle: Text(
              'En cas de problèmes d\'affichage ou de mise à jour',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.white54),
            ),
            trailing: FilledButton.icon(
              onPressed: () {
                // Show confirmation dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text('Vider le cache ?',
                        style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'Cette action va recharger l\'application et effacer les données temporaires.\n'
                      'Vos réglages et favoris sont sauvegardés sur le serveur.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange),
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
                backgroundColor: Colors.orange.withOpacity(0.2),
                foregroundColor: Colors.orange,
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
            backgroundColor: Colors.red.shade700,
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.roboto(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Ex: FR,FRANCE,HD,SPORT',
              hintStyle:
                  GoogleFonts.roboto(fontSize: 12, color: Colors.white30),
              filled: true,
              fillColor: Colors.black26,
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
                      icon: const Icon(Icons.clear,
                          size: 16, color: Colors.white54),
                      onPressed: onClear,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : null,
            ),
            style: GoogleFonts.roboto(fontSize: 12, color: Colors.white),
            onChanged: onChanged,
          ),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.map((keyword) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(50),
                    border:
                        Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    keyword,
                    style:
                        GoogleFonts.roboto(fontSize: 11, color: Colors.white),
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
