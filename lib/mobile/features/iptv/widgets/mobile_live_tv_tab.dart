import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../../../../features/iptv/providers/favorites_provider.dart';
import '../../../../features/iptv/widgets/live_widgets.dart';
import '../screens/mobile_player_screen.dart';
import '../../../../core/models/iptv_models.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

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
    final channelsAsync = ref.watch(
      liveChannelsByPlaylistProvider(widget.playlist),
    );
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(iptvSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent, // Handled by MobileScaffold
      body: channelsAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Chargement des chaînes…',
                style: AppTheme.body(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              FutureBuilder(
                future: Future.delayed(const Duration(seconds: 8)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return TextButton(
                      onPressed: () => ref.refresh(
                        liveChannelsByPlaylistProvider(widget.playlist),
                      ),
                      child: const Text('C’est long ? Réessayer'),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        error: (e, s) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  'Impossible de charger les chaînes',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  style: AppTheme.body(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.refresh(
                    liveChannelsByPlaylistProvider(widget.playlist),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (groupedChannels) {
          var categories = groupedChannels.keys.toList();
          if (settings.liveTvKeywords.isNotEmpty) {
            categories = categories
                .where((cat) => settings.matchesLiveTvFilter(cat))
                .toList();
          }
          // REMOVED alphabetic sort to respect server/settings order

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
            // If the selected category is no longer available (due to filters), reset it
            if (_selectedCategory != null &&
                !categories.contains(_selectedCategory)) {
              _selectedCategory = categories.isNotEmpty
                  ? categories.first
                  : null;
            }
            if (_selectedCategory != null) {
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
            }
          }

          final title = _searchQuery.isNotEmpty
              ? 'Résultats'
              : _showFavoritesOnly
              ? 'Favoris'
              : _selectedCategory ?? 'Chaînes';

          return SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Large title + favourites filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Direct',
                          style: AppTheme.display(
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _showFavoritesOnly
                            ? 'Toutes les chaînes'
                            : 'Chaînes favorites seulement',
                        onPressed: () => setState(
                          () => _showFavoritesOnly = !_showFavoritesOnly,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: _showFavoritesOnly
                              ? AppColors.accentFill
                              : Colors.transparent,
                        ),
                        icon: Icon(
                          _showFavoritesOnly
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: _showFavoritesOnly
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MobileSearchField(
                    controller: _searchController,
                    hint: 'Rechercher une chaîne',
                    showClear: _searchQuery.isNotEmpty,
                    onClear: () => _searchController.clear(),
                  ),
                ),

                // Categories
                if (_searchQuery.isEmpty && !_showFavoritesOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 38,
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
                              duration: AppTheme.durationFocus,
                              curve: AppTheme.curveFocus,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accentFill
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull,
                                ),
                              ),
                              child: Text(
                                category,
                                style: AppTheme.body(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // Sub-header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                  child: SectionTitle(
                    title,
                    count: displayedChannels.length,
                    fontSize: 18,
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
                                color: AppColors.textMuted,
                                size: 44,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Aucune chaîne trouvée',
                                style: AppTheme.body(
                                  fontSize: 15,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
                          itemCount: displayedChannels.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                          ),
                          itemBuilder: (context, index) {
                            final channel = displayedChannels[index];
                            return _MobileChannelTile(
                              playlist: widget.playlist,
                              channel: channel,
                              onTap: () => _playChannel(
                                context,
                                channel,
                                displayedChannels,
                              ),
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

  void _playChannel(
    BuildContext context,
    Channel channel,
    List<Channel> channels,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobilePlayerScreen(
          streamId: channel.streamId,
          title: channel.name,
          playlist: widget.playlist,
          streamType: StreamType.live,
          channels: channels,
        ),
      ),
    );
  }
}

/// Search field of the phone tabs (Direct, Films, Séries): a 48 dp `surface`
/// field, as in xtremobile. [busy] shows a small spinner (search running).
class MobileSearchField extends StatelessWidget {
  const MobileSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.showClear,
    required this.onClear,
    this.onChanged,
    this.busy = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool showClear;
  final VoidCallback onClear;
  final ValueChanged<String>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
      ),
      padding: EdgeInsets.only(left: 12, right: showClear ? 0 : 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: AppTheme.body(fontSize: 16),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.body(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (showClear)
            IconButton(
              tooltip: 'Effacer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.textMuted,
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

/// One channel, like xtremobile's phone rows: logo tile, name, programme on
/// now with its times and the red live line, and the favourite star.
class _MobileChannelTile extends ConsumerWidget {
  final PlaylistConfig playlist;
  final Channel channel;
  final VoidCallback onTap;

  const _MobileChannelTile({
    required this.playlist,
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sans ce bouton, aucun moyen d'ajouter un favori : le filtre « Favoris »
    // de l'en-tête affichait toujours une liste vide.
    final isFav = ref.watch(favoritesProvider).contains(channel.streamId);
    final now = watchEpgNow(ref, playlist, channel);
    final current = now.current;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              ChannelLogo(
                url: logoOf(channel),
                name: channel.name,
                width: 56,
                height: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: current == null ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (now.timeRange != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              now.timeRange!,
                              style: AppTheme.body(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                fontFeatures: AppTheme.tabular,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (current != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (now.progress != null) ...[
                        const SizedBox(height: 6),
                        LiveLine(
                          progress: now.progress!,
                          height: 2,
                          subdued: true,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? AppColors.accent : AppColors.textMuted,
                  size: 22,
                ),
                onPressed: () => ref
                    .read(favoritesProvider.notifier)
                    .toggleFavorite(channel.streamId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
