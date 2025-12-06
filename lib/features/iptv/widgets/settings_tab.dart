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
  late TextEditingController _filterController;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).currentUser;
    final settings = ref.watch(iptvSettingsProvider);
    
    // Sync controller with state
    if (_filterController.text != settings.categoryFilter) {
      _filterController.text = settings.categoryFilter;
    }

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
        
        // Category filter section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_list, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Live TV Category Filter',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter keywords separated by commas. Only categories containing one of these words will be shown.',
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: 'Ex: FR,FRANCE,HD,SPORT',
                    hintStyle: GoogleFonts.roboto(fontSize: 13),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: _filterController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _filterController.clear();
                              ref.read(iptvSettingsProvider.notifier)
                                  .clearCategoryFilter();
                            },
                          )
                        : null,
                  ),
                  style: GoogleFonts.roboto(fontSize: 13),
                  onChanged: (value) {
                    ref.read(iptvSettingsProvider.notifier)
                        .setCategoryFilter(value);
                  },
                ),
                if (settings.filterKeywords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: settings.filterKeywords.map((keyword) {
                      return Chip(
                        label: Text(
                          keyword,
                          style: GoogleFonts.roboto(fontSize: 11),
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
}
