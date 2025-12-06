import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/favorites_provider.dart';
import '../screens/player_screen.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/components/ui_components.dart';
import 'channel_card.dart';

/// Live TV tab - Apple TV Style with Horizontal Category Filter
class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  
  // State
  String? _selectedCategory;
  
  // UI State
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();
  bool _showFavoritesOnly = false;
  String _searchQuery = '';
  
  // Scroll Controllers
  final ScrollController _mainScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final channelsAsync = ref.watch(liveChannelsByPlaylistProvider(widget.playlist));
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(iptvSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (groupedChannels) {
           // Groups
           var categories = groupedChannels.keys.toList();
           if (settings.liveTvKeywords.isNotEmpty) {
             categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
           }
           categories.sort();
           
           // Filter Logic
           List<Channel> displayedChannels = [];
           
           if (_searchQuery.isNotEmpty) {
             // Global Search
             displayedChannels = groupedChannels.values.expand((l) => l)
                 .where((c) => c.name.toLowerCase().contains(_searchQuery))
                 .toList();
           } else if (_showFavoritesOnly) {
             // Favorites
             displayedChannels = groupedChannels.values.expand((l) => l)
                 .where((c) => favorites.contains(c.streamId))
                 .toList();
           } else if (_selectedCategory != null) {
              // Selected Category
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
           } else {
             // Default: Show first category or All if practical, but "All" is too big.
             // Apple TV pattern: Auto-select first category if nothing selected.
             if (categories.isNotEmpty) {
                // We don't want to trigger setState during build, so we just use the first category functionality
                // But visualized as "All" might be confusing with map keys.
                // Let's default to the first category in the list.
                _selectedCategory ??= categories.first;
                displayedChannels = groupedChannels[_selectedCategory] ?? [];
             }
           }

          return Column(
            children: [
              // Minimalist Header
              Container(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'Live TV',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    
                    // Search Pill
                    Container(
                      width: 250,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Search channels',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.only(bottom: 12),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () => _searchController.clear(),
                            child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary)
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Favorites Toggle
                    IconButton(
                      icon: Icon(
                        _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                        color: _showFavoritesOnly ? AppColors.error : AppColors.textSecondary,
                      ),
                      onPressed: () {
                         setState(() {
                           _showFavoritesOnly = !_showFavoritesOnly;
                           if (_showFavoritesOnly) _searchController.clear();
                         });
                      },
                      tooltip: 'Favorites Only',
                    ),
                    IconButton(
                      icon: Icon(
                        _isGridView ? Icons.view_list : Icons.grid_view,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                      tooltip: 'Toggle View',
                    ),
                  ],
                ),
              ),

              // Categories Horizontal List (Only if not searching/favorites)
              if (_searchQuery.isEmpty && !_showFavoritesOnly)
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final isSelected = category == _selectedCategory;
                      return CategoryChip(
                        label: category,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedCategory = category;
                            _mainScrollController.jumpTo(0); // Reset scroll
                          });
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 8),

              // Channels Content
              Expanded(
                child: displayedChannels.isEmpty
                  ? Center(
                      child: Text(
                        _showFavoritesOnly ? 'No favorites' : 'No channels found',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                      ),
                    )
                  : _isGridView
                      ? _buildGridView(displayedChannels)
                      : _buildListView(displayedChannels),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGridView(List<Channel> channels) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 4,
      desktop: 6,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.3, // Card ratio 4:3ish
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ChannelCard(
          streamId: channel.streamId,
          name: channel.name,
          iconUrl: _getProxiedIconUrl(channel.streamIcon),
          currentProgram: null,
          onTap: () => _playChannel(channel),
        );
      },
    );
  }

  Widget _buildListView(List<Channel> channels) {
    return ListView.separated(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return SizedBox(
          height: 70,
          child: ChannelCard(
            streamId: channel.streamId,
            name: channel.name,
            iconUrl: _getProxiedIconUrl(channel.streamIcon),
            height: 70,
            width: double.infinity,
            onTap: () => _playChannel(channel),
          ),
        );
      },
    );
  }

  String? _getProxiedIconUrl(String originalUrl) {
    if (originalUrl.isEmpty) return null;
    if (originalUrl.startsWith('http://')) {
      return '/api/xtream/$originalUrl';
    }
    return originalUrl;
  }

  void _playChannel(Channel channel) {
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
  }
}
