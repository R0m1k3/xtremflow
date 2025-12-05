import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../services/xtream_service.dart';
import '../models/xtream_models.dart';
import '../screens/video_player_screen.dart';
import 'epg_widget.dart';

class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab> {
  final ScrollController _scrollController = ScrollController();
  final List<LiveChannel> _channels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _loadMoreChannels();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreChannels();
    }
  }

  Future<void> _loadMoreChannels() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final newChannels = await service.getLiveStreams(
        offset: _currentOffset,
        limit: _pageSize,
      );

      setState(() {
        _channels.addAll(newChannels);
        _currentOffset += _pageSize;
        _hasMore = newChannels.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load channels: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_channels.isEmpty && !_isLoading) {
      return const Center(child: Text('No channels available'));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _channels.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _channels.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final channel = _channels[index];
        return _ChannelCard(
          channel: channel,
          playlist: widget.playlist,
        );
      },
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final LiveChannel channel;
  final PlaylistConfig playlist;

  const _ChannelCard({
    required this.channel,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final streamUrl = channel.getStreamUrl(
            playlist.dns,
            playlist.username,
            playlist.password,
          );
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                streamUrl: streamUrl,
                title: channel.name,
                posterUrl: channel.streamIcon,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: channel.streamIcon != null
                  ? CachedNetworkImage(
                      imageUrl: channel.streamIcon!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade800,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.live_tv, size: 48),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.live_tv, size: 48),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  // EPG Display
                  if (channel.epgChannelId != null)
                    EPGWidget(
                      channelId: channel.streamId,
                      playlist: playlist,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
