import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_colors.dart';

class MobileSettingsTab extends ConsumerStatefulWidget {
  const MobileSettingsTab({super.key});

  @override
  ConsumerState<MobileSettingsTab> createState() => _MobileSettingsTabState();
}

class _MobileSettingsTabState extends ConsumerState<MobileSettingsTab> {
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
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) _syncControllers(settings);
    });

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
         Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),

          // User Profile
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(
                    currentUser?.username.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser?.username ?? 'Guest',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (currentUser?.isAdmin ?? false)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('ADMIN', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Appearance
          _SectionHeader(title: 'Appearance'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode', style: TextStyle(color: AppColors.textPrimary)),
                  secondary:  Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary),
                  value: isDark,
                  onChanged: (_) => themeNotifier.toggleTheme(),
                  activeColor: AppColors.primary,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Show Clock', style: TextStyle(color: AppColors.textPrimary)),
                  secondary: const Icon(Icons.access_time, color: AppColors.primary),
                  value: settings.showClock,
                  onChanged: (val) => ref.read(iptvSettingsProvider.notifier).setShowClock(val),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Streaming Settings
          _SectionHeader(title: 'Streaming'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _DropdownSetting<StreamQuality>(
                  label: 'Quality',
                  icon: Icons.high_quality,
                  value: settings.streamQuality,
                  items: StreamQuality.values,
                  labelBuilder: (v) => v.name.toUpperCase(),
                  onChanged: (v) {
                    if (v != null) ref.read(iptvSettingsProvider.notifier).setStreamQuality(v);
                  },
                ),
                const Divider(height: 1),
                _DropdownSetting<BufferSize>(
                  label: 'Buffer Size',
                  icon: Icons.memory,
                  value: settings.bufferSize,
                  items: BufferSize.values,
                  labelBuilder: (v) => v.name.toUpperCase(),
                  onChanged: (v) {
                    if (v != null) ref.read(iptvSettingsProvider.notifier).setBufferSize(v);
                  },
                ),
                const Divider(height: 1),
                _DropdownSetting<ConnectionTimeout>(
                   label: 'Timeout',
                   icon: Icons.timer,
                   value: settings.connectionTimeout,
                   items: ConnectionTimeout.values,
                   labelBuilder: (v) => '${v.name.toUpperCase()} (${ref.read(iptvSettingsProvider).timeoutSeconds}s)',
                   onChanged: (v) {
                     if (v != null) ref.read(iptvSettingsProvider.notifier).setConnectionTimeout(v);
                   },
                ),
                const Divider(height: 1),
                 SwitchListTile(
                  title: const Text('Auto Reconnect', style: TextStyle(color: AppColors.textPrimary)),
                  secondary: const Icon(Icons.refresh, color: AppColors.primary),
                  value: settings.autoReconnect,
                  onChanged: (val) => ref.read(iptvSettingsProvider.notifier).setAutoReconnect(val),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Content Filters
          _SectionHeader(title: 'Content Filters'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _FilterInput(
                  label: 'Live TV Keywords',
                  icon: Icons.live_tv,
                  controller: _liveTvController,
                  onChanged: (val) => ref.read(iptvSettingsProvider.notifier).setLiveTvFilter(val),
                ),
                const Divider(height: 24),
                _FilterInput(
                  label: 'Movies Keywords',
                  icon: Icons.movie,
                  controller: _moviesController,
                  onChanged: (val) => ref.read(iptvSettingsProvider.notifier).setMoviesFilter(val),
                ),
                const Divider(height: 24),
                _FilterInput(
                  label: 'Series Keywords',
                  icon: Icons.tv,
                  controller: _seriesController,
                  onChanged: (val) => ref.read(iptvSettingsProvider.notifier).setSeriesFilter(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          if (currentUser?.isAdmin ?? false)
            _SettingsButton(
              icon: Icons.admin_panel_settings,
              label: 'Admin Panel',
              onTap: () => context.go('/admin'),
            ),
          const SizedBox(height: 12),
          _SettingsButton(
            icon: Icons.playlist_play,
            label: 'Change Playlist',
            onTap: () => context.go('/playlists'),
          ),
          const SizedBox(height: 32),
          
          FilledButton.icon(
             onPressed: () {
               ref.read(authProvider.notifier).logout();
               context.go('/login');
             },
             style: FilledButton.styleFrom(
               backgroundColor: AppColors.error.withOpacity(0.1),
               foregroundColor: AppColors.error,
               minimumSize: const Size(double.infinity, 50),
             ),
             icon: const Icon(Icons.logout),
             label: const Text('Logout'),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _FilterInput extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FilterInput({
    required this.label,
    required this.icon,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              TextField(
                controller: controller,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                  border: InputBorder.none,
                  hintText: 'e.g. FR, HD',
                ),
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DropdownSetting<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  const _DropdownSetting({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox(),
            dropdownColor: AppColors.surfaceVariant,
            icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
            style: const TextStyle(color: AppColors.textPrimary),
            items: items.map((item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
