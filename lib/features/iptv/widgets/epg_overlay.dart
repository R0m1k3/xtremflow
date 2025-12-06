import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';

/// EPG overlay widget showing "Now" and "Next" programs
class EpgOverlay extends ConsumerWidget {
  final String streamId;
  final PlaylistConfig playlist;

  const EpgOverlay({
    super.key,
    required this.streamId,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgAsync = ref.watch(epgByPlaylistProvider(
      EpgRequestKey(playlist: playlist, streamId: streamId),
    ));

    return epgAsync.when(
      data: (epgEntries) {
        if (epgEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get "Now" and "Next" programs
        final now = DateTime.now();
        final currentProgram = epgEntries.firstWhere(
          (entry) {
            final start = DateTime.parse(entry.start);
            final end = DateTime.parse(entry.end);
            return now.isAfter(start) && now.isBefore(end);
          },
          orElse: () => epgEntries.first,
        );

        final progress = currentProgram.getProgress();

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current program
              Text(
                'NOW: ${currentProgram.title}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              // Time info
              Text(
                '${_formatTime(currentProgram.start)} - ${_formatTime(currentProgram.end)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              // Description if available
              if (currentProgram.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  currentProgram.description,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Next program
              if (epgEntries.length > 1) ...[
                const SizedBox(height: 8),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 8),
                Text(
                  'NEXT: ${epgEntries[1].title}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatTime(epgEntries[1].start),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _formatTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }
}
