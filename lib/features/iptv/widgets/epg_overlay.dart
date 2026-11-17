import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../providers/xtream_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Bandeau du guide sur le lecteur : titre et description du programme en cours.
class EpgOverlay extends ConsumerWidget {
  final String streamId;
  final PlaylistConfig playlist;

  const EpgOverlay({super.key, required this.streamId, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgAsync = ref.watch(
      epgByPlaylistProvider(
        EpgRequestKey(playlist: playlist, streamId: streamId),
      ),
    );

    return epgAsync.when(
      data: (epgEntries) {
        if (epgEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get "Now" program
        final now = DateTime.now();
        final currentProgram = epgEntries.firstWhere((entry) {
          final start = EpgEntry.parseDateTime(entry.start);
          final end = EpgEntry.parseDateTime(entry.end);
          if (start == null || end == null) return false;
          return now.isAfter(start) && now.isBefore(end);
        }, orElse: () => epgEntries.first);

        // Enhanced info display
        return Align(
          alignment: Alignment.bottomLeft, // Align to bottom left near controls
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 0, 24, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // Over the video: an opaque-ish graphite panel stays legible on
            // a bright picture.
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'En direct',
                    style: AppTheme.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500), // Wider
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentProgram.title,
                        style: AppTheme.display(fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (currentProgram.description.isNotEmpty)
                        Text(
                          currentProgram.description,
                          style: AppTheme.body(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
