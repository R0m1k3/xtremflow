import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../providers/settings_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Réglages du streaming du direct.
class StreamingSettingsTab extends ConsumerWidget {
  const StreamingSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(iptvSettingsProvider);
    final notifier = ref.read(iptvSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Text('Streaming du direct', style: AppTheme.display(fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          'Ces paramètres s\'appliquent uniquement aux flux TV en direct.',
          style: AppTheme.body(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // Note: Player type is now automatically determined:
        // - Live TV uses Player Lite (MPEG-TS)
        // - Movies/Series use Player Standard

        // Quality Section
        _buildSectionCard(
          context: context,
          title: 'Qualité vidéo',
          icon: Icons.high_quality,
          children: [
            _buildDropdownTile<StreamQuality>(
              title: 'Qualité du flux',
              subtitle: 'Débit : ${settings.bitrateKbps} kbps',
              value: settings.streamQuality,
              items: StreamQuality.values,
              onChanged: (v) => notifier.setStreamQuality(v!),
              labelBuilder: (v) => switch (v) {
                StreamQuality.low => 'Faible (1,5 Mbit/s)',
                StreamQuality.medium => 'Moyen (3 Mbit/s)',
                StreamQuality.high => 'Élevé (5 Mbit/s)',
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Buffer Section
        _buildSectionCard(
          context: context,
          title: 'Tampon et latence',
          icon: Icons.speed,
          children: [
            _buildDropdownTile<BufferSize>(
              title: 'Taille du tampon',
              subtitle: 'Segments HLS : ${settings.hlsSegmentDuration}s',
              value: settings.bufferSize,
              items: BufferSize.values,
              onChanged: (v) => notifier.setBufferSize(v!),
              labelBuilder: (v) => switch (v) {
                BufferSize.low => 'Faible (latence min)',
                BufferSize.medium => 'Moyen (équilibré)',
                BufferSize.high => 'Élevé (stabilité max)',
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Connection Section
        _buildSectionCard(
          context: context,
          title: 'Connexion',
          icon: Icons.wifi,
          children: [
            _buildDropdownTile<ConnectionTimeout>(
              title: 'Délai de connexion',
              subtitle: '${settings.timeoutSeconds} secondes',
              value: settings.connectionTimeout,
              items: ConnectionTimeout.values,
              onChanged: (v) => notifier.setConnectionTimeout(v!),
              labelBuilder: (v) => switch (v) {
                ConnectionTimeout.short => 'Court (15 s)',
                ConnectionTimeout.medium => 'Moyen (30 s)',
                ConnectionTimeout.long => 'Long (60 s)',
              },
            ),
            const Divider(height: 1, color: AppColors.hairline),
            SwitchListTile(
              title: Text(
                'Reconnexion automatique',
                style: AppTheme.body(fontSize: 15),
              ),
              subtitle: Text(
                'Se reconnecter en cas de coupure',
                style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
              ),
              value: settings.autoReconnect,
              onChanged: (v) => notifier.setAutoReconnect(v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Transcoding Section
        _buildSectionCard(
          context: context,
          title: 'Transcodage',
          icon: Icons.transform,
          children: [
            _buildDropdownTile<TranscodingMode>(
              title: 'Mode de transcodage',
              subtitle: 'Comment le flux est traité',
              value: settings.transcodingMode,
              items: TranscodingMode.values,
              onChanged: (v) => notifier.setTranscodingMode(v!),
              labelBuilder: (v) => switch (v) {
                TranscodingMode.auto => 'Auto (recommandé)',
                TranscodingMode.forced => 'Forcé (toujours transcoder)',
                TranscodingMode.disabled => 'Désactivé (direct)',
              },
            ),
            const Divider(height: 1, color: AppColors.hairline),
            SwitchListTile(
              title: Text(
                'Préférer la lecture directe',
                style: AppTheme.body(fontSize: 15),
              ),
              subtitle: Text(
                'Utiliser le flux original si compatible',
                style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
              ),
              value: settings.preferDirectPlay,
              onChanged: (v) => notifier.setPreferDirectPlay(v),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Cache Section
        _buildSectionCard(
          context: context,
          title: 'Cache EPG',
          icon: Icons.schedule,
          children: [
            _buildDropdownTile<EpgCacheDuration>(
              title: 'Durée du cache EPG',
              subtitle: '${settings.epgCacheMinutes} minutes',
              value: settings.epgCacheDuration,
              items: EpgCacheDuration.values,
              onChanged: (v) => notifier.setEpgCacheDuration(v!),
              labelBuilder: (v) => switch (v) {
                EpgCacheDuration.short => 'Court (5 min)',
                EpgCacheDuration.medium => 'Moyen (15 min)',
                EpgCacheDuration.long => 'Long (1 heure)',
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Server/GPU Section
        _buildSectionCard(
          context: context,
          title: 'Serveur / GPU',
          icon: Icons.memory,
          children: [
            SwitchListTile(
              title: Text(
                'Accélération GPU NVIDIA',
                style: AppTheme.body(fontSize: 15),
              ),
              subtitle: Text(
                'Utiliser NVENC/NVDEC pour le transcodage (requiert GPU NVIDIA)',
                style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
              ),
              value: settings.enableNvidiaGpu,
              onChanged: (v) => notifier.setEnableNvidiaGpu(v),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Info card
        GlassContainer(
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Les changements prennent effet immédiatement pour les nouveaux flux.',
                  style: AppTheme.body(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: AppTheme.body(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.hairline),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDropdownTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    required String Function(T) labelBuilder,
  }) {
    return ListTile(
      title: Text(title, style: AppTheme.body(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
      ),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        dropdownColor: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        focusColor: Colors.transparent,
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(labelBuilder(item), style: AppTheme.body(fontSize: 14)),
          );
        }).toList(),
        onChanged: onChanged,
        style: AppTheme.body(fontSize: 14),
        iconEnabledColor: AppColors.textMuted,
      ),
    );
  }
}
