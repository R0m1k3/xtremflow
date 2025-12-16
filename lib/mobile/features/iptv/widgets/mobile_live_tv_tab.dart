import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../../../../features/iptv/providers/favorites_provider.dart';
import '../screens/mobile_player_screen.dart';
import '../../../../core/models/iptv_models.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';

class MobileLiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileLiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileLiveTVTab> createState() => _MobileLiveTVTabState();
}

class _MobileLiveTVTabState extends ConsumerState<MobileLiveTVTab> {
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync =
        ref.watch(liveChannelsByPlaylistProvider(widget.playlist));
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(iptvSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent, // Handled by MobileScaffold
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white)),
        ),
        data: (groupedChannels) {
          var categories = groupedChannels.keys.toList();
          if (settings.liveTvKeywords.isNotEmpty) {
            categories = categories
                .where((cat) => settings.matchesLiveTvFilter(cat))
                .toList();
          }
          categories.sort();

          List<Channel> displayedChannels = [];
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
          } else {
            if (_selectedCategory == null && categories.isNotEmpty) {
              _selectedCategory = categories.first;
            }
            if (_selectedCategory != null) {
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
            }
          }

          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Header & Search
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassContainer(
                    borderRadius: 16,
                    opacity: 0.1,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.inter(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Search channels...',
                              hintStyle:
                                  GoogleFonts.inter(color: Colors.white54),
                              border: InputBorder.none,
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.white54,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () => _searchController.clear(),
                            child:
                                const Icon(Icons.close, color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                ),

                // Categories
                if (_searchQuery.isEmpty && !_showFavoritesOnly)
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final isSelected = category == _selectedCategory;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedCategory = category),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category,
                              style: GoogleFonts.inter(
                                color:
                                    isSelected ? Colors.black : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Sub-header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Results'
                            : _showFavoritesOnly
                                ? 'Favorites'
                                : _selectedCategory ?? 'Channels',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(
                          () => _showFavoritesOnly = !_showFavoritesOnly,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _showFavoritesOnly
                                ? AppColors.live.withOpacity(0.2)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
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
                                : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: displayedChannels.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.tv_off,
                                color: Colors.white24,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No channels found',
                                style: GoogleFonts.inter(color: Colors.white38),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: displayedChannels.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final channel = displayedChannels[index];
                            return _MobileChannelTile(
                              channel: channel,
                              playlist: widget.playlist,
                              onTap: () => _playChannel(context, channel),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _playChannel(BuildContext context, Channel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobilePlayerScreen(
          streamId: channel.streamId,
          title: channel.name,
          playlist: widget.playlist,
          streamType: StreamType.live,
        ),
      ),
    );
  }
}

class _MobileChannelTile extends ConsumerWidget {
  final Channel channel;
  final PlaylistConfig playlist;
  final VoidCallback onTap;

  const _MobileChannelTile({
    required this.channel,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconUrl =
        channel.streamIcon.isNotEmpty && channel.streamIcon.startsWith('http')
            ? '/api/xtream/${channel.streamIcon}'
            : null;

    // Fetch EPG
    final epgAsync = ref.watch(
      epgByPlaylistProvider(
        EpgRequestKey(playlist: playlist, streamId: channel.streamId),
      ),
    );

    return GlassContainer(
      borderRadius: 12,
      opacity: 0.15,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: iconUrl != null
                    ? Image.network(
                        iconUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.tv, color: Colors.white24),
                      )
                    : const Icon(Icons.tv, color: Colors.white24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // EPG Only (Replaces Channel Number)
                    epgAsync.when(
                      data: (epgList) {
                        if (epgList.isEmpty) {
                          return Text(
                            'No Info',
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          );
                        }
                        final current = epgList.first;
                        return Text(
                          current.title,
                          style: GoogleFonts.inter(
                            color: const Color(
                              0xFFFFD700,
                            ), // Gold/Amber for visibility check
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                      loading: () => const Text(
                        '...',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      error: (err, stack) => const Text(
                        'Err',
                        style: TextStyle(color: Colors.red, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
