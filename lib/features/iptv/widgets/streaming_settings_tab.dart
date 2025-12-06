import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/settings_provider.dart';

/// Streaming settings tab for Live TV configuration
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
        Text(
          'Paramètres Streaming Live TV',
          style: GoogleFonts.roboto(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ces paramètres s\'appliquent uniquement aux flux TV en direct.',
          style: GoogleFonts.roboto(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 24),

        // Quality Section
        _buildSectionCard(
          context: context,
          title: 'Qualité Vidéo',
          icon: Icons.high_quality,
          children: [
            _buildDropdownTile<StreamQuality>(
              title: 'Qualité du flux',
              subtitle: 'Bitrate: ${settings.bitrateKbps} kbps',
              value: settings.streamQuality,
              items: StreamQuality.values,
              onChanged: (v) => notifier.setStreamQuality(v!),
              labelBuilder: (v) => switch (v) {
                StreamQuality.low => 'Faible (1.5 Mbps)',
                StreamQuality.medium => 'Moyen (3 Mbps)',
                StreamQuality.high => 'Élevé (5 Mbps)',
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Buffer Section
        _buildSectionCard(
          context: context,
          title: 'Buffer & Latence',
          icon: Icons.speed,
          children: [
            _buildDropdownTile<BufferSize>(
              title: 'Taille du buffer',
              subtitle: 'Segments HLS: ${settings.hlsSegmentDuration}s',
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
              title: 'Timeout de connexion',
              subtitle: '${settings.timeoutSeconds} secondes',
              value: settings.connectionTimeout,
              items: ConnectionTimeout.values,
              onChanged: (v) => notifier.setConnectionTimeout(v!),
              labelBuilder: (v) => switch (v) {
                ConnectionTimeout.short => 'Court (15s)',
                ConnectionTimeout.medium => 'Moyen (30s)',
                ConnectionTimeout.long => 'Long (60s)',
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: Text(
                'Reconnexion automatique',
                style: GoogleFonts.roboto(fontSize: 14),
              ),
              subtitle: Text(
                'Se reconnecter en cas de coupure',
                style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey),
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
            const Divider(height: 1),
            SwitchListTile(
              title: Text(
                'Préférer lecture directe',
                style: GoogleFonts.roboto(fontSize: 14),
              ),
              subtitle: Text(
                'Utiliser le flux original si compatible',
                style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey),
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
        const SizedBox(height: 32),

        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Les changements prennent effet immédiatement pour les nouveaux flux.',
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: Colors.blue.shade700,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
      title: Text(title, style: GoogleFonts.roboto(fontSize: 14)),
      subtitle: Text(subtitle, style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey)),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(
              labelBuilder(item),
              style: GoogleFonts.roboto(fontSize: 13),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
