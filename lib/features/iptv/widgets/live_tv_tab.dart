import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/player_screen.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import 'epg_widget.dart';

/// Live TV tab with category box grid navigation
class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  String? _selectedCategory;
  int _currentPage = 0;
  static const int _itemsPerPage = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final channelsAsync = ref.watch(liveChannelsByPlaylistProvider(widget.playlist));

    return channelsAsync.when(
      data: (groupedChannels) {
        if (groupedChannels.isEmpty) {
          return const Center(
            child: Text('No live channels available'),
          );
        }

        // If a category is selected, show channels list
        if (_selectedCategory != null && groupedChannels.containsKey(_selectedCategory)) {
          return _buildChannelsList(groupedChannels[_selectedCategory]!);
        }

        // Otherwise show category grid
        return _buildCategoryGrid(groupedChannels);
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

  /// Build the category grid view with box cards
  Widget _buildCategoryGrid(Map<String, List<Channel>> groupedChannels) {
    // Get filter settings
    final settings = ref.watch(iptvSettingsProvider);
    
    // Filter categories based on keywords
    var categories = groupedChannels.keys.toList();
    if (settings.liveTvKeywords.isNotEmpty) {
      categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
    }
    categories.sort();

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.filter_list_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No categories match the filter',
              style: GoogleFonts.roboto(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Filter: ${settings.liveTvCategoryFilter}',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.8,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final channelCount = groupedChannels[category]!.length;
          
          return _CategoryBox(
            categoryName: category,
            channelCount: channelCount,
            onTap: () {
              setState(() {
                _selectedCategory = category;
                _currentPage = 0;
              });
            },
          );
        },
      ),
    );
  }

  /// Build channels list for selected category
  Widget _buildChannelsList(List<Channel> channels) {
    final totalPages = (channels.length / _itemsPerPage).ceil();
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage > channels.length)
        ? channels.length
        : startIndex + _itemsPerPage;
    final paginatedChannels = channels.sublist(startIndex, endIndex);

    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                    _currentPage = 0;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedCategory ?? '',
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${channels.length} channels',
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),

        // Pagination controls
        if (totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $totalPages',
                    style: GoogleFonts.roboto(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < totalPages - 1
                      ? () => setState(() => _currentPage++)
                      : null,
                ),
              ],
            ),
          ),

        // Channels list
        Expanded(
          child: ListView.builder(
            itemCount: paginatedChannels.length,
            itemBuilder: (context, index) {
              final channel = paginatedChannels[index];
              return _buildChannelTile(context, channel);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelTile(BuildContext context, Channel channel) {
    // Accept both HTTP and HTTPS icons - use proxy for HTTP
    final bool hasIcon = channel.streamIcon.isNotEmpty;
    String iconUrl = channel.streamIcon;
    
    // Proxy HTTP images through our server to avoid Mixed Content blocking
    if (hasIcon && channel.streamIcon.startsWith('http://')) {
      iconUrl = '/api/xtream/${Uri.encodeComponent(channel.streamIcon)}';
    }
    
    final Widget placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.tv, color: Colors.white54),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PlayerScreen(
                streamId: channel.streamId,
                title: channel.name,
                playlist: widget.playlist,
                streamType: StreamType.live,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Channel icon
              hasIcon
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: iconUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => placeholder,
                        errorWidget: (context, url, error) => placeholder,
                      ),
                    )
                  : placeholder,
              const SizedBox(width: 12),
              
              // Channel info + EPG
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // EPG info
                    EPGWidget(
                      channelId: channel.streamId,
                      playlist: widget.playlist,
                    ),
                  ],
                ),
              ),
              
              // Play button
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category box card widget
class _CategoryBox extends StatelessWidget {
  final String categoryName;
  final int channelCount;
  final VoidCallback onTap;

  const _CategoryBox({
    required this.categoryName,
    required this.channelCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.15),
                Theme.of(context).colorScheme.secondary.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.live_tv,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$channelCount',
                        style: GoogleFonts.roboto(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  categoryName,
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
