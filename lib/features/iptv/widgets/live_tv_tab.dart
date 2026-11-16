import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/favorites_provider.dart';
import '../screens/player_screen.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/navigation/search_requests.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/group_label.dart';
import '../../../core/widgets/themed_loading_screen.dart';
import '../../../core/widgets/tv_focusable.dart';
import 'live_preview_controller.dart';
import 'live_preview_view.dart';
import 'live_widgets.dart';
import 'recording_modal.dart';

/// Onglet Direct : favoris de groupes, tous les groupes, puis la liste des
/// chaînes d'un groupe avec, à droite, le panneau « en ce moment » et son
/// aperçu vidéo muet.
class LiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const LiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<LiveTVTab> createState() => _LiveTVTabState();
}

/// What the channel list shows.
enum _ListKind { group, favorites, search }

class _LiveTVTabState extends ConsumerState<LiveTVTab>
    with AutomaticKeepAliveClientMixin {
  static const _tabIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'live-search');
  String _query = '';

  /// Open group (category name), or « Chaînes favorites ».
  String? _openGroup;
  bool _favoritesOpen = false;

  /// Channel under the mouse or the keyboard focus, and its number.
  Channel? _current;
  int _currentNumber = 0;

  LivePreviewNotifier get _preview => ref.read(livePreviewProvider.notifier);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q == _query) return;
      setState(() {
        _query = q;
        _current = null;
      });
      _preview.stop();
    });
    searchRequests.addListener(_onSearchRequest);
  }

  @override
  void dispose() {
    searchRequests.removeListener(_onSearchRequest);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _onSearchRequest() {
    if (activeTab.value != _tabIndex || !mounted) return;
    _searchFocus.requestFocus();
  }

  bool get _inList => _query.isNotEmpty || _favoritesOpen || _openGroup != null;

  void _openList({String? group, bool favorites = false}) {
    setState(() {
      _openGroup = group;
      _favoritesOpen = favorites;
      _current = null;
    });
  }

  /// Back to the groups (Échap, Retour).
  void _back() {
    _preview.stop();
    setState(() {
      _openGroup = null;
      _favoritesOpen = false;
      _current = null;
      if (_query.isNotEmpty) _searchController.clear();
    });
  }

  void _onChannelFocus(Channel channel, int number) {
    if (_current?.streamId != channel.streamId) {
      setState(() {
        _current = channel;
        _currentNumber = number;
      });
    }
    _requestPreview(channel);
  }

  void _requestPreview(Channel channel) {
    final enabled = ref.read(iptvSettingsProvider).livePreview;
    _preview.setEnabled(enabled);
    if (!enabled) return;
    final ts = ref
        .read(xtreamServiceProvider(widget.playlist))
        .getLiveStreamUrlTs(channel.streamId);
    _preview.request(channel.streamId, ts);
  }

  Future<void> _play(Channel channel, List<Channel> contextList) async {
    // The preview gives its connection back before the full screen opens.
    _preview.stop();
    await Navigator.of(context).push(
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
    if (!mounted || activeTab.value != _tabIndex) return;
    final current = _current;
    if (current != null && _inList) _requestPreview(current);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final channelsAsync = ref.watch(
      liveChannelsByPlaylistProvider(widget.playlist),
    );
    final settings = ref.watch(iptvSettingsProvider);

    return channelsAsync.when(
      loading: () => const ThemedLoading(),
      error: (e, s) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Impossible de charger les chaînes',
              style: AppTheme.body(fontSize: 16),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
              onPressed: () => ref.invalidate(
                liveChannelsByPlaylistProvider(widget.playlist),
              ),
            ),
          ],
        ),
      ),
      data: (grouped) {
        var categories = grouped.keys.toList();
        if (settings.liveTvKeywords.isNotEmpty) {
          categories = categories
              .where((c) => settings.matchesLiveTvFilter(c))
              .toList();
        }
        return _inList
            ? _buildChannelView(grouped, categories, settings)
            : _buildGroupsView(grouped, categories);
      },
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _searchField() {
    return SizedBox(
      width: 340,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        cursorColor: AppColors.accent,
        style: AppTheme.body(fontSize: 15),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher une chaîne',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: _searchController.clear,
                ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _header({required Widget title, Widget? leading}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 18),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 14)],
          Expanded(child: title),
          const SizedBox(width: 16),
          _searchField(),
        ],
      ),
    );
  }

  // ─── Groups ────────────────────────────────────────────────────────────────

  Widget _buildGroupsView(
    Map<String, List<Channel>> grouped,
    List<String> categories,
  ) {
    final favorites = ref.watch(favoritesProvider);
    ref.watch(favoriteCategoriesProvider);
    final pins = ref.read(favoriteCategoriesProvider.notifier);
    final playlistId = widget.playlist.id;
    final pinned = pins
        .categoriesOf(playlistId)
        .where((c) => grouped.containsKey(c))
        .toList();
    final favoriteCount = grouped.values
        .expand((l) => l)
        .where((c) => favorites.contains(c.streamId))
        .length;

    final favoriteCards = <Widget>[
      if (favoriteCount > 0)
        FavoriteGroupCard(
          category: (name: 'Chaînes favorites', count: favoriteCount),
          icon: Icons.star_rounded,
          onPressed: () => _openList(favorites: true),
        ),
      for (final name in pinned)
        FavoriteGroupCard(
          category: (name: name, count: grouped[name]?.length ?? 0),
          onPressed: () => _openList(group: name),
          onTogglePin: () => pins.toggle(playlistId, name),
        ),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _header(
            title: Text(
              'Direct',
              style: AppTheme.display(
                fontSize: 30,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (favoriteCards.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(32, 6, 32, 12),
            sliver: SliverToBoxAdapter(child: SectionTitle('Favoris')),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 84,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildListDelegate(favoriteCards),
            ),
          ),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 12),
          sliver: SliverToBoxAdapter(
            child: SectionTitle('Tous les groupes', count: categories.length),
          ),
        ),
        if (categories.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 32),
              child: Text(
                'Aucun groupe : vérifiez le filtre des catégories dans Réglages.',
                style: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: 76,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final name = categories[i];
              return TvGroupCard(
                label: GroupLabel.parse(name),
                count: grouped[name]?.length ?? 0,
                pinned: pins.isFavorite(playlistId, name),
                onPressed: () => _openList(group: name),
                onTogglePin: () => pins.toggle(playlistId, name),
              );
            }, childCount: categories.length),
          ),
        ),
      ],
    );
  }

  // ─── Channels ──────────────────────────────────────────────────────────────

  Widget _buildChannelView(
    Map<String, List<Channel>> grouped,
    List<String> categories,
    IptvSettings settings,
  ) {
    final favorites = ref.watch(favoritesProvider);
    final _ListKind kind;
    final List<Channel> channels;
    if (_query.isNotEmpty) {
      kind = _ListKind.search;
      channels = [
        for (final cat in categories)
          for (final c in grouped[cat] ?? const <Channel>[])
            if (c.name.toLowerCase().contains(_query)) c,
      ];
    } else if (_favoritesOpen) {
      kind = _ListKind.favorites;
      channels = grouped.values
          .expand((l) => l)
          .where((c) => favorites.contains(c.streamId))
          .toList();
    } else {
      kind = _ListKind.group;
      channels = grouped[_openGroup] ?? const [];
    }

    final label = kind == _ListKind.group
        ? GroupLabel.parse(_openGroup!)
        : GroupLabel(
            name: kind == _ListKind.search ? 'Recherche' : 'Chaînes favorites',
          );
    final count = '${channels.length} chaîne${channels.length > 1 ? 's' : ''}';
    final subtitle = [
      if (label.country != null &&
          label.country!.toLowerCase() != label.name.toLowerCase())
        label.country!,
      count,
    ].join(' · ');

    final current = _current;
    final preview = current != null && settings.livePreview
        ? LivePreviewView(channel: current)
        : null;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _back();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            leading: _BackButton(onPressed: _back),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.body(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final panelWidth = math.min(box.maxWidth * .4, 560.0);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 32, 28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: channels.isEmpty
                            ? Center(
                                child: Text(
                                  kind == _ListKind.search
                                      ? 'Aucune chaîne ne correspond'
                                      : 'Aucune chaîne',
                                  style: AppTheme.body(
                                    fontSize: 15,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                key: PageStorageKey(
                                  'live-${kind.name}-$_openGroup',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                itemExtent: ChannelRow.height + 4,
                                itemCount: channels.length,
                                itemBuilder: (context, i) {
                                  final c = channels[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: ChannelRow(
                                      key: ValueKey(c.streamId),
                                      playlist: widget.playlist,
                                      channel: c,
                                      number: i + 1,
                                      autofocus:
                                          i == 0 && kind != _ListKind.search,
                                      isFavorite: favorites.contains(
                                        c.streamId,
                                      ),
                                      onFocus: () => _onChannelFocus(c, i + 1),
                                      onPressed: () => _play(c, channels),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: panelWidth,
                        child: NowPanel(
                          playlist: widget.playlist,
                          channel: current,
                          number: _currentNumber,
                          isFavorite:
                              current != null &&
                              favorites.contains(current.streamId),
                          preview: preview,
                          onFullScreen: () {
                            if (current != null) _play(current, channels);
                          },
                          onToggleFavorite: () {
                            if (current == null) return;
                            ref
                                .read(favoritesProvider.notifier)
                                .toggleFavorite(current.streamId);
                          },
                          onRecord: () {
                            if (current != null) {
                              RecordingModal.show(context, current);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Retour aux groupes (Échap)',
      child: TVFocusable(
        paintsOwnFocus: true,
        scale: 1.0,
        borderRadius: BorderRadius.circular(12),
        onPressed: onPressed,
        child: Builder(
          builder: (context) {
            final lit = TVFocusable.isFocused(context);
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: lit ? AppColors.focusTop : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                color: lit ? AppColors.onFocus : AppColors.textPrimary,
              ),
            );
          },
        ),
      ),
    );
  }
}
