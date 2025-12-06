import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'streaming_settings_tab.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';

/// Main Settings tab with sub-tabs for Filters, Streaming, and Appearance
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _liveTvController;
  late TextEditingController _moviesController;
  late TextEditingController _seriesController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    if (!_initialized || _liveTvController.text != settings.liveTvCategoryFilter) {
      _liveTvController.text = settings.liveTvCategoryFilter;
    }
    if (!_initialized || _moviesController.text != settings.moviesCategoryFilter) {
      _moviesController.text = settings.moviesCategoryFilter;
    }
    if (!_initialized || _seriesController.text != settings.seriesCategoryFilter) {
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
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.filter_list), text: 'Filtres'),
              Tab(icon: Icon(Icons.stream), text: 'Streaming'),
              Tab(icon: Icon(Icons.palette), text: 'Apparence'),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.dark_mode,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Thème',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
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
        ),
        
        const SizedBox(height: 16),
        
        // Quick toggle card
        Card(
          child: ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: AppColors.primary,
            ),
            title: Text(
              'Mode actuel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              isDark ? 'Thème sombre actif' : 'Thème clair actif',
            ),
            trailing: Switch(
              value: isDark,
              onChanged: (_) => themeNotifier.toggleTheme(),
              activeColor: AppColors.primary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
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
                          ? AppColors.primary
                          : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersTab(BuildContext context, dynamic currentUser, IptvSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User info card
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(
              'Connecté en tant que',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey),
            ),
            subtitle: Text(
              currentUser?.username ?? 'Unknown',
              style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
            ),
            trailing: currentUser?.isAdmin ?? false
                ? Chip(
                    label: Text('Admin', style: GoogleFonts.roboto(fontSize: 11)),
                    backgroundColor: Colors.blue.shade100,
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
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Seules les catégories contenant un de ces mots-clés seront affichées. Séparez par des virgules.',
          style: GoogleFonts.roboto(
            fontSize: 12,
            color: Colors.grey.shade600,
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
        
        // Admin panel
        if (currentUser?.isAdmin ?? false) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text('Panneau Admin', style: GoogleFonts.roboto()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/admin'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // Change playlist
        Card(
          child: ListTile(
            leading: const Icon(Icons.playlist_play),
            title: Text('Changer de Playlist', style: GoogleFonts.roboto()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 8),
        
        // About
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('À propos', style: GoogleFonts.roboto()),
            subtitle: Text(
              'XtremFlow IPTV v1.0.0',
              style: GoogleFonts.roboto(fontSize: 12),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Ex: FR,FRANCE,HD,SPORT',
                hintStyle: GoogleFonts.roboto(fontSize: 12),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: onClear,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
              ),
              style: GoogleFonts.roboto(fontSize: 12),
              onChanged: onChanged,
            ),
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: keywords.map((keyword) {
                  return Chip(
                    label: Text(
                      keyword,
                      style: GoogleFonts.roboto(fontSize: 10),
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
