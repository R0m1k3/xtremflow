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
import 'channel_card.dart';

/// Live TV tab - Enhanced with Search, Favorites and Grid/List View
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
  int _currentPage = 0;
  static const int _itemsPerPage = 100; // Increased for grid view
  
  // UI State
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();
  bool _showFavoritesOnly = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _currentPage = 0; // Reset page on search
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final channelsAsync = ref.watch(liveChannelsByPlaylistProvider(widget.playlist));
    final favorites = ref.watch(favoritesProvider);

    return Scaffold( // Use scaffold for toolbar body structure
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Toolbar
          _buildToolbar(),

          // Content
          Expanded(
            child: channelsAsync.when(
              data: (groupedChannels) {
                // 1. Flatten for global search/filter if needed
                final allChannels = groupedChannels.values.expand((element) => element).toList();
                
                List<Channel> displayedChannels = [];
                bool isGlobalMode = _searchQuery.isNotEmpty || _showFavoritesOnly;

                if (isGlobalMode) {
                  // Global Filter Mode
                  displayedChannels = allChannels.where((channel) {
                    final matchesSearch = _searchQuery.isEmpty || 
                        channel.name.toLowerCase().contains(_searchQuery);
                    final matchesFavorite = !_showFavoritesOnly || 
                        favorites.contains(channel.streamId);
                    return matchesSearch && matchesFavorite;
                  }).toList();
                } else if (_selectedCategory != null) {
                  // Category Mode
                  displayedChannels = groupedChannels[_selectedCategory] ?? [];
                }

                // If no global mode and no category selected, show Category Grid
                if (!isGlobalMode && _selectedCategory == null) {
                  if (groupedChannels.isEmpty) {
                    return const Center(child: Text('No channels found'));
                  }
                  return _buildCategoryGrid(groupedChannels);
                }

                // Show Channels (Grid or List)
                if (displayedChannels.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tv_off, size: 64, color: AppColors.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          _showFavoritesOnly ? 'No favorites found' : 'No channels found',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  );
                }

                return _buildChannelsView(displayedChannels, isGlobalMode);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Search Bar
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search channels...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: AppColors.surface.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Favorites Toggle
          IconButton(
            tooltip: 'Favorites Only',
            icon: Icon(
              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
              color: _showFavoritesOnly ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _showFavoritesOnly = !_showFavoritesOnly;
                _selectedCategory = null; // Reset category when toggling favorites
                _currentPage = 0;
              });
            },
          ),

          // View Toggle
          IconButton(
            tooltip: _isGridView ? 'List View' : 'Grid View',
            icon: Icon(
              _isGridView ? Icons.view_list : Icons.grid_view,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(Map<String, List<Channel>> groupedChannels) {
    final settings = ref.watch(iptvSettingsProvider);
    var categories = groupedChannels.keys.toList();
    
    // Apply Settings Filter (Hidden categories)
    if (settings.liveTvKeywords.isNotEmpty) {
      categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
    }
    categories.sort();

    final crossAxisCount = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 3,
      desktop: 5,
    );

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final count = groupedChannels[category]!.length;
        
        return InkWell(
          onTap: () => setState(() {
            _selectedCategory = category;
            _currentPage = 0;
          }),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppColors.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface.withOpacity(0.8),
                  AppColors.surface,
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: Icon(
                    Icons.tv,
                    size: 80,
                    color: Colors.white.withOpacity(0.03),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        category,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$count channels',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelsView(List<Channel> channels, bool isGlobalMode) {
    // Pagination
    final totalPages = (channels.length / _itemsPerPage).ceil();
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage > channels.length) 
        ? channels.length 
        : startIndex + _itemsPerPage;
    final pageChannels = channels.sublist(startIndex, endIndex);

    return Column(
      children: [
        // Breadcrumb / Back Navigation
        if (!isGlobalMode && _selectedCategory != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface.withOpacity(0.5),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () => setState(() => _selectedCategory = null),
                  tooltip: 'Back to Categories',
                ),
                Text(
                  _selectedCategory!,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                Text(
                  '${channels.length} items',
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

        // Grid/List Content
        Expanded(
          child: _isGridView 
              ? _buildGridView(pageChannels) 
              : _buildListView(pageChannels),
        ),

        // Pagination Controls
        if (totalPages > 1)
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                ),
                Text(
                  'Page ${_currentPage + 1} of $totalPages',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                ),
              ],
            ),
          ),
      ],
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
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.4, // Card ratio
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ChannelCard(
          streamId: channel.streamId, // Now required
          name: channel.name,
          iconUrl: _getProxiedIconUrl(channel.streamIcon),
          currentProgram: null, // ShortEPG requires async fetch
          onTap: () => _playChannel(channel),
        );
      },
    );
  }

  Widget _buildListView(List<Channel> channels) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return SizedBox(
          height: 80, // Fixed height for list item
          child: ChannelCard(
            streamId: channel.streamId,
            name: channel.name,
            iconUrl: _getProxiedIconUrl(channel.streamIcon),
            height: 80,
            width: double.infinity, // Full width
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
