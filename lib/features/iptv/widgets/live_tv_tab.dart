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
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/themed_loading_screen.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';
import 'recording_modal.dart';

class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  String? _selectedCategory;
  final bool _isGridView = true;
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

    final channelsAsync =
        ref.watch(liveChannelsByPlaylistProvider(widget.playlist));
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(iptvSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: channelsAsync.when(
        loading: () => const ThemedLoading(),
        error: (e, s) => Center(
          child: Text(
            'Error: $e',
            style: GoogleFonts.inter(color: AppColors.onSurface),
          ),
        ),
        data: (groupedChannels) {
          var categories = groupedChannels.keys.toList();
          if (settings.liveTvKeywords.isNotEmpty) {
            categories = categories
                .where((cat) => settings.matchesLiveTvFilter(cat))
                .toList();
          }

          List<Channel> displayedChannels = [];
          bool showingCategoryGrid = false;

          if (_searchQuery.isNotEmpty) {
            displayedChannels = groupedChannels.values
                .expand((l) => l)
                .where((c) => c.name.toLowerCase().contains(_searchQuery))
                .toList();
          } else if (_showFavoritesOnly) {
            displayedChannels = groupedChannels.values
                .expand((l) => l)
                .where((c) => favorites.contains(c.streamId))
                .toList();
          } else if (_selectedCategory != null) {
            displayedChannels = groupedChannels[_selectedCategory] ?? [];
          } else {
            showingCategoryGrid = true;
          }

          return Column(
            children: [
              // HEADER (Glass Level 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: GlassContainer.glass(
                  borderRadius: 16,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      if (_selectedCategory != null &&
                          _searchQuery.isEmpty &&
                          !_showFavoritesOnly) ...[
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
                              color: AppColors.surfaceContainerHigh
                                  .withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      Expanded(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Search Results'
                              : _showFavoritesOnly
                                  ? 'Favorites'
                                  : _selectedCategory ?? 'Live TV',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
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
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.inter(color: AppColors.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Search channels...',
                            hintStyle:
                                GoogleFonts.inter(color: AppColors.outline),
                            prefixIcon:
                                Icon(Icons.search, color: AppColors.outline),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: AppColors.onSurface,
                                    ),
                                    onPressed: _searchController.clear,
                                  )
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
                            color: _showFavoritesOnly
                                ? AppColors.live.withOpacity(0.2)
                                : AppColors.surfaceContainerHigh
                                    .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: _showFavoritesOnly
                                ? Border.all(color: AppColors.live)
                                : null,
                          ),
                          child: Icon(
                            _showFavoritesOnly
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _showFavoritesOnly
                                ? AppColors.live
                                : AppColors.onSurfaceVariant,
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
                                Icon(
                                  Icons.tv_off,
                                  size: 64,
                                  color: AppColors.outline,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No channels found',
                                  style: GoogleFonts.inter(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _buildChannelGrid(displayedChannels),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryGrid(
    List<String> categories,
    Map<String, List<Channel>> groupedChannels,
  ) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 4,
      desktop: 6,
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
          child: GlassContainer.glass(
            borderRadius: 16,
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.surfaceContainerLow.withOpacity(0.5),
                        AppColors.primary.withOpacity(0.03),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_copy_outlined,
                        color: AppColors.onSurfaceVariant,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          category,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count Channels',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.outline,
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

  Widget _buildChannelGrid(List<Channel> channels) {
    final columns = ResponsiveLayout.value(
      context,
      mobile: 2,
      tablet: 5,
      desktop: 8,
    );

    return GridView.builder(
      controller: _mainScrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return TvFocusableCard(
          onTap: () => _playChannel(channel, channels),
          borderRadius: 12,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon Area
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer
                              .withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: channel.streamIcon.isNotEmpty
                              ? Image.network(
                                  _getProxiedIconUrl(channel.streamIcon)!,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.tv,
                                    color: AppColors.outline,
                                    size: 40,
                                  ),
                                )
                              : Text(
                                  channel.name.characters.first.toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.outlineVariant,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh.withOpacity(0.9),
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            style: GoogleFonts.inter(
                              color: AppColors.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Consumer(
                            builder: (context, ref, _) {
                              final epgAsync = ref.watch(
                                epgByPlaylistProvider(
                                  EpgRequestKey(
                                    playlist: widget.playlist,
                                    streamId: channel.streamId,
                                  ),
                                ),
                              );

                              return epgAsync.when(
                                data: (epgList) {
                                  if (epgList.isEmpty) {
                                    return Text(
                                      'No Info',
                                      style: GoogleFonts.inter(
                                        color: AppColors.outline,
                                        fontSize: 10,
                                      ),
                                    );
                                  }
                                  final now = DateTime.now();
                                  final currentProgram = epgList.firstWhere(
                                    (entry) {
                                      try {
                                        final start =
                                            EpgEntry.parseDateTime(entry.start);
                                        final end =
                                            EpgEntry.parseDateTime(entry.end);
                                        if (start == null || end == null)
                                          return false;
                                        return now.isAfter(start) &&
                                            now.isBefore(end);
                                      } catch (e) {
                                        return false;
                                      }
                                    },
                                    orElse: () => epgList.first,
                                  );

                                  return Text(
                                    currentProgram.title,
                                    style: GoogleFonts.inter(
                                      color: AppColors.ratingGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                                loading: () => Text(
                                  '...',
                                  style: GoogleFonts.inter(
                                    color: AppColors.outlineVariant,
                                    fontSize: 10,
                                  ),
                                ),
                                error: (_, __) => Text(
                                  'Err',
                                  style: GoogleFonts.inter(
                                    color: AppColors.error,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Record Button Icon Overlay
                Positioned(
                  top: 8,
                  right: 8,
                  child: TvFocusableCard(
                    onTap: () {
                      RecordingModal.show(context, channel);
                    },
                    borderRadius: 20,
                    scaleFactor: 1.2,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.fiber_manual_record,
                        color: AppColors.error,
                        size: 16,
                      ),
                    ),
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
