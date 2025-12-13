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
import '../../../core/widgets/themed_loading_screen.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import 'channel_card.dart';

class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  
  String? _selectedCategory;
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();
  bool _showFavoritesOnly = false;
  String _searchQuery = '';
  final ScrollController _mainScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
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
        loading: () => const ThemedLoading(),
        error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
        data: (groupedChannels) {
           var categories = groupedChannels.keys.toList();
           if (settings.liveTvKeywords.isNotEmpty) {
             categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
           }
           categories.sort();
           
           List<Channel> displayedChannels = [];
           bool showingCategoryGrid = false;
           
           if (_searchQuery.isNotEmpty) {
             displayedChannels = groupedChannels.values.expand((l) => l)
                 .where((c) => c.name.toLowerCase().contains(_searchQuery))
                 .toList();
           } else if (_showFavoritesOnly) {
             displayedChannels = groupedChannels.values.expand((l) => l)
                 .where((c) => favorites.contains(c.streamId))
                 .toList();
           } else if (_selectedCategory != null) {
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
           } else {
             showingCategoryGrid = true;
           }

          return Column(
            children: [
              // HEADER (Glass)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: GlassContainer(
                  borderRadius: 16,
                  opacity: 0.6,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      if (_selectedCategory != null && _searchQuery.isEmpty && !_showFavoritesOnly) ...[
                        TvFocusableCard(
                          onTap: () {
                             setState(() {
                                _selectedCategory = null;
                                _mainScrollController.jumpTo(0);
                             });
                          },
                          borderRadius: 50,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      Expanded(
                        child: Text(
                          _searchQuery.isNotEmpty ? 'Search Results' : 
                          _showFavoritesOnly ? 'Favorites' :
                          _selectedCategory ?? 'Live TV',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Search Bar
                      Container(
                        width: 250,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.inter(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search channels...',
                            hintStyle: GoogleFonts.inter(color: Colors.white54),
                            prefixIcon: const Icon(Icons.search, color: Colors.white54),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            suffixIcon: _searchQuery.isNotEmpty 
                              ? IconButton(icon: const Icon(Icons.clear, color: Colors.white), onPressed: _searchController.clear)
                              : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Favorites Toggle
                      TvFocusableCard(
                        onTap: () {
                           setState(() {
                             _showFavoritesOnly = !_showFavoritesOnly;
                             if (_showFavoritesOnly) _searchController.clear();
                             _selectedCategory = null;
                           });
                        },
                        borderRadius: 12,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _showFavoritesOnly ? AppColors.live.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: _showFavoritesOnly ? Border.all(color: AppColors.live) : null,
                          ),
                          child: Icon(
                            _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                            color: _showFavoritesOnly ? AppColors.live : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // GRID / LIST AREA
              Expanded(
                child: showingCategoryGrid
                    ? _buildCategoryGrid(categories, groupedChannels)
                    : displayedChannels.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.tv_off, size: 64, color: Colors.white.withOpacity(0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  'No channels found',
                                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 18),
                                ),
                              ],
                            ),
                          )
                        // Use raw grid for now, but wrapped in focusable cards
                        : _buildChannelGrid(displayedChannels),
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
      desktop: 4,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.all(24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 1.6,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final count = groupedChannels[category]?.length ?? 0;
        
        return TvFocusableCard(
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _mainScrollController.jumpTo(0);
            });
          },
          borderRadius: 16,
          child: GlassContainer(
            borderRadius: 16,
            opacity: 0.2, // Darker glass
            padding: const EdgeInsets.all(0),
            child: Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.05),
                        Colors.blue.withOpacity(0.05),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_copy_outlined, color: Colors.white.withOpacity(0.9), size: 32),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          category,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count Channels',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
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

  Widget _buildChannelGrid(List<Channel> channels) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 4,
      desktop: 5,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.0, // Square-ish cards
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return TvFocusableCard(
          onTap: () => _playChannel(channel, channels),
          borderRadius: 12,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon Area
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: channel.streamIcon.isNotEmpty 
                        ? Image.network(
                            _getProxiedIconUrl(channel.streamIcon)!,
                            errorBuilder: (_,__,___) => const Icon(Icons.tv, color: Colors.grey, size: 40),
                          )
                        : Text(
                            channel.name.characters.first.toUpperCase(),
                            style: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black12),
                          ),
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black54,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Consumer(
                        builder: (context, ref, _) {
                            final epgAsync = ref.watch(epgByPlaylistProvider(
                              EpgRequestKey(playlist: widget.playlist, streamId: channel.streamId)
                            ));
                            
                            return epgAsync.when(
                              data: (epgList) {
                                if (epgList.isEmpty) {
                                  return Text('No Info', style: GoogleFonts.inter(color: Colors.white54, fontSize: 10));
                                }
                                final now = DateTime.now();
                                final currentProgram = epgList.firstWhere(
                                  (entry) {
                                    try {
                                      final start = DateTime.parse(entry.start);
                                      final end = DateTime.parse(entry.end);
                                      return now.isAfter(start) && now.isBefore(end);
                                    } catch (e) {
                                      return false;
                                    }
                                  },
                                  orElse: () => epgList.first,
                                );

                                return Text(
                                  currentProgram.title,
                                  style: GoogleFonts.inter(color: const Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                              loading: () => Text('...', style: GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
                              error: (_,__) => Text('Err', style: GoogleFonts.inter(color: Colors.red, fontSize: 10)),
                            );
                        }
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

  String? _getProxiedIconUrl(String originalUrl) {
    if (originalUrl.isEmpty) return null;
    if (originalUrl.startsWith('http://')) {
      return '/api/xtream/$originalUrl';
    }
    return originalUrl;
  }

  void _playChannel(Channel channel, List<Channel> contextList) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamId: channel.streamId,
          title: channel.name,
          playlist: widget.playlist,
          streamType: StreamType.live,
          channels: contextList,
        ),
      ),
    );
  }
}
