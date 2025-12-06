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
import '../../../theme/mobile_theme.dart';
import '../../../../core/widgets/components/ui_components.dart'; // For images/CachedNetworkImage if needed

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
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(liveChannelsByPlaylistProvider(widget.playlist));
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(iptvSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (groupedChannels) {
          // Prepare categories
          var categories = groupedChannels.keys.toList();
          if (settings.liveTvKeywords.isNotEmpty) {
            categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
          }
          categories.sort();

          // Prepare channels
          List<Channel> displayedChannels = [];
          if (_searchQuery.isNotEmpty) {
            displayedChannels = groupedChannels.values.expand((l) => l)
                .where((c) => c.name.toLowerCase().contains(_searchQuery))
                .toList();
          } else if (_showFavoritesOnly) {
            displayedChannels = groupedChannels.values.expand((l) => l)
                .where((c) => favorites.contains(c.streamId))
                .toList();
          } else {
            // Default to first category if none selected
            if (_selectedCategory == null && categories.isNotEmpty) {
               _selectedCategory = categories.first;
            }
            if (_selectedCategory != null) {
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
            }
          }

          return SafeArea(
            bottom: false, // For bottom nav
            child: Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Search channels',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () => _searchController.clear(),
                            child: const Icon(Icons.close, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),

                // Categories (Chips)
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
                        return ChoiceChip(
                          label: Text(category),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            }
                          },
                          backgroundColor: AppColors.surface,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          side: BorderSide.none,
                          showCheckmark: false,
                        );
                      },
                    ),
                  ),
                
                // Content Switcher (Favorites button etc)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        _searchQuery.isNotEmpty ? 'Search Results' : 
                        _showFavoritesOnly ? 'Favorites' : 
                        _selectedCategory ?? 'All Channels',
                        style: const TextStyle(
                          color: AppColors.textPrimary, 
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                          color: _showFavoritesOnly ? AppColors.error : AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
                      ),
                    ],
                  ),
                ),

                // Channel List
                Expanded(
                  child: displayedChannels.isEmpty
                      ? Center(
                          child: Text(
                            'No channels found',
                            style: GoogleFonts.inter(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80), // Bottom padding for FAB/Nav
                          itemCount: displayedChannels.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final channel = displayedChannels[index];
                            return _MobileChannelTile(
                              channel: channel,
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

class _MobileChannelTile extends StatelessWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _MobileChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconUrl = channel.streamIcon.isNotEmpty && channel.streamIcon.startsWith('http') 
        ? '/api/xtream/${channel.streamIcon}' 
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: iconUrl != null
                  ? Image.network(
                      iconUrl, 
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white24),
                    )
                  : const Icon(Icons.tv, color: Colors.white24),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: Text(
                channel.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Play Icon
            const Icon(Icons.play_circle_outline, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
