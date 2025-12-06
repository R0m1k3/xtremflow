import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  late TextEditingController _liveTvController;
  late TextEditingController _moviesController;
  late TextEditingController _seriesController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _liveTvController = TextEditingController();
    _moviesController = TextEditingController();
    _seriesController = TextEditingController();
  }

  @override
  void dispose() {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User info card
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(
              'Logged in as',
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
          'Category Filters',
          style: GoogleFonts.roboto(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Only categories containing one of these keywords will be shown. Separate with commas.',
          style: GoogleFonts.roboto(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        
        // Live TV Filter
        _buildFilterCard(
          title: 'Live TV Filter',
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
          title: 'Movies Filter',
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
          title: 'Series Filter',
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
              title: Text('Admin Panel', style: GoogleFonts.roboto()),
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
            title: Text('Change Playlist', style: GoogleFonts.roboto()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 8),
        
        // About
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('About', style: GoogleFonts.roboto()),
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
          label: const Text('Logout'),
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
