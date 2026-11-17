import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/glass.dart';

class MobileSettingsTab extends ConsumerStatefulWidget {
  const MobileSettingsTab({super.key});

  @override
  ConsumerState<MobileSettingsTab> createState() => _MobileSettingsTabState();
}

class _MobileSettingsTabState extends ConsumerState<MobileSettingsTab> {
  late TextEditingController _liveTvController;
  late TextEditingController _moviesController;
  late final TextEditingController _seriesController;
  late final TextEditingController _backendUrlController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _liveTvController = TextEditingController();
    _moviesController = TextEditingController();
    _seriesController = TextEditingController();
    _backendUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _liveTvController.dispose();
    _moviesController.dispose();
    _seriesController.dispose();
    _backendUrlController.dispose();
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
    if (!_initialized || _backendUrlController.text != settings.backendUrl) {
      _backendUrlController.text = settings.backendUrl;
    }
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).currentUser;
    final settings = ref.watch(iptvSettingsProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) _syncControllers(settings);
    });

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
            child: Text(
              'Réglages',
              style: AppTheme.display(
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // User Profile
          _Group(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.accentFill,
                    child: Text(
                      currentUser?.username.substring(0, 1).toUpperCase() ??
                          'U',
                      style: AppTheme.body(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?.username ?? 'Invité',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (currentUser?.isAdmin ?? false)
                          Text(
                            'Administrateur',
                            style: AppTheme.body(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Display (the charter is dark only: no theme switch)
          const _SectionHeader(title: 'Affichage'),
          _Group(
            children: [
              _SwitchRow(
                icon: Icons.access_time,
                label: 'Afficher l’horloge',
                value: settings.showClock,
                onChanged: (val) =>
                    ref.read(iptvSettingsProvider.notifier).setShowClock(val),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Streaming Settings
          const _SectionHeader(title: 'Lecture'),
          _Group(
            children: [
              _DropdownSetting<StreamQuality>(
                label: 'Qualité',
                icon: Icons.high_quality_outlined,
                value: settings.streamQuality,
                items: StreamQuality.values,
                labelBuilder: (v) => switch (v) {
                  StreamQuality.low => 'Faible',
                  StreamQuality.medium => 'Moyenne',
                  StreamQuality.high => 'Élevée',
                },
                onChanged: (v) {
                  if (v != null) {
                    ref.read(iptvSettingsProvider.notifier).setStreamQuality(v);
                  }
                },
              ),
              const Divider(height: 1, indent: 52),
              _DropdownSetting<BufferSize>(
                label: 'Mémoire tampon',
                icon: Icons.memory,
                value: settings.bufferSize,
                items: BufferSize.values,
                labelBuilder: (v) => switch (v) {
                  BufferSize.low => 'Faible',
                  BufferSize.medium => 'Moyenne',
                  BufferSize.high => 'Élevée',
                },
                onChanged: (v) {
                  if (v != null) {
                    ref.read(iptvSettingsProvider.notifier).setBufferSize(v);
                  }
                },
              ),
              const Divider(height: 1, indent: 52),
              _DropdownSetting<ConnectionTimeout>(
                label: 'Délai d’attente',
                icon: Icons.timer_outlined,
                value: settings.connectionTimeout,
                items: ConnectionTimeout.values,
                labelBuilder: (v) {
                  final name = switch (v) {
                    ConnectionTimeout.short => 'Court',
                    ConnectionTimeout.medium => 'Moyen',
                    ConnectionTimeout.long => 'Long',
                  };
                  return '$name (${ref.read(iptvSettingsProvider).timeoutSeconds} s)';
                },
                onChanged: (v) {
                  if (v != null) {
                    ref
                        .read(iptvSettingsProvider.notifier)
                        .setConnectionTimeout(v);
                  }
                },
              ),
              const Divider(height: 1, indent: 52),
              _DropdownSetting<TranscodingMode>(
                label: 'Transcodage',
                icon: Icons.settings_input_component_outlined,
                value: settings.transcodingMode,
                items: TranscodingMode.values,
                labelBuilder: (v) {
                  switch (v) {
                    case TranscodingMode.auto:
                      return 'Auto';
                    case TranscodingMode.forced:
                      return 'Forcé';
                    case TranscodingMode.disabled:
                      return 'Direct';
                  }
                },
                onChanged: (v) {
                  if (v != null) {
                    ref
                        .read(iptvSettingsProvider.notifier)
                        .setTranscodingMode(v);
                  }
                },
              ),
              const Divider(height: 1, indent: 52),
              _SwitchRow(
                icon: Icons.refresh,
                label: 'Reconnexion automatique',
                value: settings.autoReconnect,
                onChanged: (val) => ref
                    .read(iptvSettingsProvider.notifier)
                    .setAutoReconnect(val),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const _SectionHeader(title: 'Serveur'),
          _Group(
            padding: const EdgeInsets.all(16),
            children: [
              _FilterInput(
                label: 'Adresse du serveur (remplace l’adresse par défaut)',
                hint: 'https://…',
                icon: Icons.lan_outlined,
                controller: _backendUrlController,
                onChanged: (val) =>
                    ref.read(iptvSettingsProvider.notifier).setBackendUrl(val),
              ),
              if (settings.backendUrl.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 32),
                  child: Text(
                    'Adresse utilisée : ${Uri.base.origin}',
                    style: AppTheme.body(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Content Filters
          const _SectionHeader(title: 'Filtres de contenu'),
          _Group(
            padding: const EdgeInsets.all(16),
            children: [
              _FilterInput(
                label: 'Mots-clés du direct',
                icon: Icons.live_tv_outlined,
                controller: _liveTvController,
                onChanged: (val) => ref
                    .read(iptvSettingsProvider.notifier)
                    .setLiveTvFilter(val),
              ),
              const Divider(height: 24),
              _FilterInput(
                label: 'Mots-clés des films',
                icon: Icons.movie_outlined,
                controller: _moviesController,
                onChanged: (val) => ref
                    .read(iptvSettingsProvider.notifier)
                    .setMoviesFilter(val),
              ),
              const Divider(height: 24),
              _FilterInput(
                label: 'Mots-clés des séries',
                icon: Icons.layers_outlined,
                controller: _seriesController,
                onChanged: (val) => ref
                    .read(iptvSettingsProvider.notifier)
                    .setSeriesFilter(val),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Actions
          if (currentUser?.isAdmin ?? false) ...[
            _SettingsButton(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Administration',
              onTap: () => context.go('/admin'),
            ),
            const SizedBox(height: 12),
          ],
          _SettingsButton(
            icon: Icons.playlist_play,
            label: 'Changer de playlist',
            // L'IPTV active, pour savoir d'où viennent guide, enregistrements
            // et Auto NBA avant d'en changer.
            value: ref.watch(selectedPlaylistProvider)?.name,
            onTap: () => context.go('/playlists'),
          ),
          const SizedBox(height: 32),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(authProvider.notifier).logout();
                context.go('/login');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorContainer,
                foregroundColor: AppColors.onErrorContainer,
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of settings on blur-free glass.
class _Group extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _Group({
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const GlassDecoration(radius: AppTheme.radiusXl, halo: false),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: AppTheme.eyebrow(fontSize: 14)),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label, style: AppTheme.body(fontSize: 16)),
      secondary: Icon(icon, color: AppColors.textSecondary),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _FilterInput extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FilterInput({
    required this.label,
    required this.icon,
    required this.controller,
    required this.onChanged,
    this.hint = 'ex. FR, HD',
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
              Text(
                label,
                style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
              ),
              TextField(
                controller: controller,
                style: AppTheme.body(fontSize: 16),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: hint,
                  hintStyle: AppTheme.body(
                    fontSize: 16,
                    color: AppColors.textMuted,
                  ),
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

  /// Valeur courante de ce réglage, affichée sous le libellé.
  final String? value;
  final VoidCallback onTap;

  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppTheme.radiusLg));
    return DecoratedBox(
      decoration: const GlassDecoration(radius: AppTheme.radiusLg, halo: false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textSecondary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTheme.body(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (value != null)
                        Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
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
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: AppTheme.body(fontSize: 16))),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox(),
            dropdownColor: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppTheme.radiusField),
            icon: const Icon(Icons.expand_more, color: AppColors.textMuted),
            style: AppTheme.body(fontSize: 15, color: AppColors.textSecondary),
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
