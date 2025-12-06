import 'package:flutter/material.dart';
import '../../../../features/iptv/screens/player_screen.dart';
import '../../../../core/models/playlist_config.dart';

/// Mobile wrapper for the PlayerScreen.
/// Currently reuses the desktop PlayerScreen as it adapts well to mobile (video player),
/// but allows for future mobile-specific overlays or gesture controls.
class MobilePlayerScreen extends StatelessWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String containerExtension;
  final PlaylistConfig playlist;

  const MobilePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
  });

  @override
  Widget build(BuildContext context) {
    // For now, we reuse the existing PlayerScreen which is responsive.
    // In the future, we can add Mobile-specific gesture detectors here.
    return PlayerScreen(
      streamId: streamId,
      title: title,
      playlist: playlist,
      streamType: streamType,
      containerExtension: containerExtension,
    );
  }
}
