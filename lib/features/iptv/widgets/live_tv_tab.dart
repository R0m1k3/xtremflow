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
           bool showingCategoryGrid = false;
           
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
              // Selected Category View
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
           } else {
             // Category Grid View (Default)
             showingCategoryGrid = true;
           }

          return Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  children: [
                    // Back Button (if in category view and not searching)
                    if (_selectedCategory != null && _searchQuery.isEmpty && !_showFavoritesOnly) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        onPressed: () {
                          setState(() {
                            _selectedCategory = null;
                            _mainScrollController.jumpTo(0);
                          });
                        },
                        tooltip: 'Back to Categories',
                      ),
                      const SizedBox(width: 8),
                    ],

                    Text(
                      _searchQuery.isNotEmpty ? 'Search Results' : 
                      _showFavoritesOnly ? 'Favorites' :
                      _selectedCategory ?? 'Live TV',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    
                    // Search Pill
                    Container(
                      width: 300,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Search channels',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.only(bottom: 11),
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
                           _selectedCategory = null; // Reset selection when toggling favorites
                         });
                      },
                      tooltip: 'Favorites Only',
                    ),
                    
                    // View Toggle (Only show when not in category grid)
                    if (!showingCategoryGrid)
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

              // Content
              Expanded(
                child: showingCategoryGrid
                    ? _buildCategoryGrid(categories, groupedChannels)
                    : displayedChannels.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty ? 'No channels found' : 
                              _showFavoritesOnly ? 'No favorites' : 'No channels in this group',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                            ),
                          )
                        : _isGridView
                            ? _buildChannelGrid(displayedChannels)
                            : _buildChannelList(displayedChannels),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryGrid(List<String> categories, Map<String, List<Channel>> groupedChannels) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 3,
      desktop: 5,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.all(24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final count = groupedChannels[category]?.length ?? 0;
        
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedCategory = category;
                _mainScrollController.jumpTo(0);
              });
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surface,
                    AppColors.surface.withOpacity(0.8),
                  ],
                ),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.folder_open, color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count Channels',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelGrid(List<Channel> channels) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 4,
      desktop: 6,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ChannelCard(
          streamId: channel.streamId,
          name: channel.name,
          iconUrl: _getProxiedIconUrl(channel.streamIcon),
          currentProgram: null,
          playlist: widget.playlist,
          onTap: () => _playChannel(channel),
        );
      },
    );
  }

  Widget _buildChannelList(List<Channel> channels) {
    return ListView.separated(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
            playlist: widget.playlist,
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
