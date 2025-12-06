import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';

/// Minimal EPG overlay - shows briefly then fades out
class EpgOverlay extends ConsumerStatefulWidget {
  final String streamId;
  final PlaylistConfig playlist;

  const EpgOverlay({
    super.key,
    required this.streamId,
    required this.playlist,
  });

  @override
  ConsumerState<EpgOverlay> createState() => _EpgOverlayState();
}

class _EpgOverlayState extends ConsumerState<EpgOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0, // Start visible
    );
    // Auto-hide after 5 seconds
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _fadeController.reverse(); // Fade out
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epgAsync = ref.watch(epgByPlaylistProvider(
      EpgRequestKey(playlist: widget.playlist, streamId: widget.streamId),
    ));

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

        // Minimal info display - just title and time
        return FadeTransition(
          opacity: _fadeController,
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      currentProgram.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
