import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/iptv/screens/player_screen.dart';
export '../../../../features/iptv/screens/player_screen.dart' show StreamType;
import '../../../../core/models/playlist_config.dart';
import '../../../../features/iptv/widgets/lite_player_view.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';

class MobilePlayerScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(xtreamServiceProvider(playlist));
    String streamUrl = '';

    if (streamType == StreamType.live) {
      streamUrl = service.getLiveStreamUrl(streamId);
    } else if (streamType == StreamType.vod) {
      streamUrl = service.getVodStreamUrl(streamId, containerExtension);
    } else if (streamType == StreamType.series) {
      streamUrl = service.getSeriesStreamUrl(streamId, containerExtension);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: LitePlayerView(
          streamUrl: streamUrl,
          isLive: streamType == StreamType.live,
        ),
      ),
    );
  }
}
