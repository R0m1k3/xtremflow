import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';


/// Minimal EPG overlay - shows program title and info
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
    ),);

    return epgAsync.when(
      data: (epgEntries) {
        if (epgEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get "Now" program
        final now = DateTime.now();
        final currentProgram = epgEntries.firstWhere(
          (entry) {
            final start = DateTime.parse(entry.start);
            final end = DateTime.parse(entry.end);
            return now.isAfter(start) && now.isBefore(end);
          },
          orElse: () => epgEntries.first,
        );

        // Enhanced info display
        return Align(
            alignment: Alignment.bottomLeft, // Align to bottom left near controls
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5), // Semi-transparent backing for readability
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12, // Larger
                        fontWeight: FontWeight.bold,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18, // Much Larger
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (currentProgram.description.isNotEmpty)
                           Text(
                            currentProgram.description,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13, // Larger desc
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
