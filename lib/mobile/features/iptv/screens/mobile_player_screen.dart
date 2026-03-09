import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/iptv/screens/player_screen.dart';
export '../../../../features/iptv/screens/player_screen.dart' show StreamType;
import '../../../../core/models/playlist_config.dart';

class MobilePlayerScreen extends ConsumerWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String containerExtension;
  final PlaylistConfig playlist;
  final List<dynamic>? channels;
  final double? startTime;

  const MobilePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
    this.channels,
    this.startTime,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the premium PlayerScreen which handles IFrames and custom overlays
    // This removes the redundant AppBar and fixes full-screen/controls issues
    return PlayerScreen(
      key: ValueKey('player-$streamId'),
      streamId: streamId,
      title: title,
      playlist: playlist,
      streamType: streamType,
      containerExtension: containerExtension,
      channels: channels,
      startTime: startTime,
    );
  }
}
