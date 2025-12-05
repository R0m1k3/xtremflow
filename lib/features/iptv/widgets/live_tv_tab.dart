import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/xtream_provider.dart';
import '../screens/player_screen.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';

/// Live TV tab with group-based pagination
class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, int> _currentPages = {};
  final Map<String, bool> _expandedCategories = {};
  static const int _itemsPerPage = 100;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final service = ref.watch(xtreamServiceProvider(widget.playlist));
    final channelsAsync = ref.watch(liveChannelsByPlaylistProvider(widget.playlist));

    return channelsAsync.when(
      data: (groupedChannels) {
        if (groupedChannels.isEmpty) {
          return const Center(
            child: Text('No live channels available'),
          );
        }

        final categories = groupedChannels.keys.toList()..sort();

        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final channels = groupedChannels[category]!;
            final currentPage = _currentPages[category] ?? 0;
            final isExpanded = _expandedCategories[category] ?? false;

            // Calculate pagination
            final totalPages = (channels.length / _itemsPerPage).ceil();
            final startIndex = currentPage * _itemsPerPage;
            final endIndex = (startIndex + _itemsPerPage > channels.length)
                ? channels.length
                : startIndex + _itemsPerPage;
            final paginatedChannels = channels.sublist(startIndex, endIndex);

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ExpansionPanelList(
                expansionCallback: (panelIndex, expanded) {
                  setState(() {
                    _expandedCategories[category] = !expanded;
                  });
                },
                children: [
                  ExpansionPanel(
                    headerBuilder: (context, isExpanded) {
                      return ListTile(
                        title: Text(
                          category,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        subtitle: Text('${channels.length} channels'),
                      );
                    },
                    body: Column(
                      children: [
                        // Pagination controls
                        if (totalPages > 1)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: currentPage > 0
                                      ? () {
                                          setState(() {
                                            _currentPages[category] = currentPage - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text(
                                  'Page ${currentPage + 1} of $totalPages',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: currentPage < totalPages - 1
                                      ? () {
                                          setState(() {
                                            _currentPages[category] = currentPage + 1;
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        // Channel list
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: paginatedChannels.length,
                          itemExtent: 72,
                          itemBuilder: (context, channelIndex) {
                            final channel = paginatedChannels[channelIndex];
                            return _buildChannelTile(context, channel);
                          },
                        ),
                      ],
                    ),
                    isExpanded: isExpanded,
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading channels: $error'),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTile(BuildContext context, Channel channel) {
    return ListTile(
      leading: channel.streamIcon.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: channel.streamIcon,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Icon(Icons.tv),
              errorWidget: (context, url, error) => const Icon(Icons.broken_image),
            )
          : const Icon(Icons.tv),
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: channel.num.isNotEmpty
          ? Text('Ch. ${channel.num}')
          : null,
      trailing: const Icon(Icons.play_circle_outline),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              streamId: channel.streamId,
              title: channel.name,
              streamType: StreamType.live,
            ),
          ),
        );
      },
    );
  }
}
