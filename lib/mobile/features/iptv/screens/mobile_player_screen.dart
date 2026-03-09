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
  final List<dynamic>? channels; // New: List of channels for zapping

  const MobilePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    this.streamType = StreamType.live,
    this.containerExtension = 'mp4',
    this.channels,
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

    // Zapping logic
    VoidCallback? onNext;
    VoidCallback? onPrevious;

    if (channels != null && channels!.isNotEmpty) {
      final currentIndex = channels!.indexWhere((c) {
        try {
          // Supports Channel/Movie (.streamId) and Episode (.id)
          final cId = (c.streamId ?? c.id).toString();
          return cId == streamId;
        } catch (_) {
          return false;
        }
      });

      if (currentIndex != -1) {
        void navigateTo(int index) {
          final item = channels![index % channels!.length];
          String nId = '';
          String nTitle = '';
          String nExt = containerExtension;

          try {
            // ID Extraction
            nId = (item.streamId ?? item.id).toString();
            // Title Extraction (name for channels/movies, title for episodes)
            nTitle = item.name ?? item.title ?? 'Unknown';

            // Format series title predictably
            if (streamType == StreamType.series && title.contains(' - ')) {
              final prefix = title.split(' - ').first;
              nTitle = '$prefix - Episode ${item.episodeNum ?? ""}';
            }

            nExt = item.containerExtension ?? containerExtension;
          } catch (_) {}

          if (nId.isEmpty) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MobilePlayerScreen(
                streamId: nId,
                title: nTitle,
                playlist: playlist,
                streamType: streamType,
                containerExtension: nExt,
                channels: channels,
              ),
            ),
          );
        }

        onNext = () => navigateTo(currentIndex + 1);
        onPrevious = () => navigateTo(currentIndex - 1 + channels!.length);
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SizedBox.expand(
        child: LitePlayerView(
          streamUrl: streamUrl,
          isLive: streamType == StreamType.live,
          onNext: onNext,
          onPrevious: onPrevious,
        ),
      ),
    );
  }
}
