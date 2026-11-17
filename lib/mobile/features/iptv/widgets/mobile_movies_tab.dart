import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/components/hero_carousel.dart';
import '../../../../features/iptv/providers/watch_history_provider.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../screens/mobile_player_screen.dart';
import '../../../../core/theme/app_theme.dart';
import 'mobile_live_tv_tab.dart' show MobileSearchField;

class MobileMoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileMoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileMoviesTab> createState() => _MobileMoviesTabState();
}

class _MobileMoviesTabState extends ConsumerState<MobileMoviesTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Movie> _movies = [];
  List<Movie>? _searchResults;
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 50;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMoreMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoading &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreMovies();
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _searchResults = null;
        _isSearching = false;
      }
    });

    if (query.length >= 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _performSearch(query);
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final results = await service.searchMovies(query);

      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final newMovies = await service.getMoviesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          _movies.addAll(newMovies);
          _currentOffset += _pageSize;
          _hasMore = newMovies.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _formatRating(String? rating) {
    if (rating == null || rating.isEmpty) return null;
    final value = double.tryParse(rating);
    if (value != null) {
      return value.toStringAsFixed(1);
    }
    return rating;
  }

  String _getProxiedImageUrl(String? originalUrl, WidgetRef ref) {
    if (originalUrl == null || originalUrl.isEmpty) return '';
    if (originalUrl.startsWith('http')) {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      // Re-use core _wrapWithProxy logic (via a new public method or direct construction)
      return '${service.backendBaseUrl}/api/xtream/$originalUrl';
    }
    return originalUrl;
  }

  void _playMovie(Movie movie, List<Movie> movies) {
    ref.read(watchHistoryProvider.notifier).markMovieWatched(movie.streamId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MobilePlayerScreen(
          streamId: movie.streamId,
          title: movie.name,
          playlist: widget.playlist,
          streamType: StreamType.vod,
          containerExtension: movie.containerExtension ?? 'mp4',
          channels: movies, // Pass list for zapping
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);
    final watchHistory = ref.watch(watchHistoryProvider);

    List<Movie> displayMovies;
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      displayMovies = _searchResults!;
    } else {
      displayMovies = settings.moviesKeywords.isEmpty
          ? _movies
          : _movies
                .where((m) => settings.matchesMoviesFilter(m.categoryName))
                .toList();
    }

    final heroItems = displayMovies
        .take(3)
        .map(
          (m) => HeroItem(
            id: m.streamId,
            title: m.name,
            imageUrl: _getProxiedImageUrl(m.streamIcon, ref),
            subtitle: m.rating != null ? 'Note ${_formatRating(m.rating)}' : null,
            onMoreInfo: () => _playMovie(m, displayMovies),
          ),
        )
        .toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Large title + search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Films',
                style: AppTheme.display(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: MobileSearchField(
                controller: _searchController,
                hint: 'Rechercher un film',
                showClear: _searchQuery.isNotEmpty,
                busy: _isSearching,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              ),
            ),
          ),

          // Hero Section
          if (_searchQuery.isEmpty && heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  height: 250,
                  child: HeroCarousel(
                    items: heroItems,
                    onTap: (item) {
                      final movie = _movies.firstWhere(
                        (element) => element.streamId == item.id,
                      );
                      _playMovie(movie, _movies);
                    },
                  ),
                ),
              ),
            ),

          // Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                return SliverGrid(
                  gridDelegate: MobilePosterTile.gridDelegate(
                    constraints.crossAxisExtent,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= displayMovies.length) return null;
                    final movie = displayMovies[index];
                    final rating = _formatRating(movie.rating);
                    return MobilePosterTile(
                      title: movie.name,
                      imageUrl: _getProxiedImageUrl(movie.streamIcon, ref),
                      meta: rating == null ? null : '$rating / 10',
                      isWatched: watchHistory.isMovieWatched(movie.streamId),
                      placeholderIcon: Icons.movie_outlined,
                      onTap: () => _playMovie(movie, displayMovies),
                      onLongPress: () {
                        ref
                            .read(watchHistoryProvider.notifier)
                            .toggleMovieWatched(movie.streamId);
                      },
                    );
                  }, childCount: displayMovies.length),
                );
              },
            ),
          ),

          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// A movie or series poster, as in xtremobile's phone layout: the artwork
/// carries the colour (light edge so dark posters stay off the page), a
/// quiet caption underneath, a small neutral check when watched.
class MobilePosterTile extends StatelessWidget {
  const MobilePosterTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.onLongPress,
    this.meta,
    this.isWatched = false,
    this.placeholderIcon = Icons.movie_outlined,
  });

  final String title;

  /// Already proxied; empty when the item has no artwork.
  final String imageUrl;
  final String? meta;
  final bool isWatched;
  final IconData placeholderIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const double _radius = 10;
  static const double _caption = 44;
  static const double _gap = 12;

  /// Columns of about 150 dp (3 on most phones), poster 2:3 + caption.
  static SliverGridDelegate gridDelegate(double width) {
    final columns = (width / 150).floor().clamp(2, 6);
    final tile = (width - (columns - 1) * _gap) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: _gap,
      mainAxisSpacing: 16,
      mainAxisExtent: tile * 1.5 + _caption,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: AppColors.cardEdge),
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    else
                      _placeholder(),
                    if (isWatched)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: _caption,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (meta != null)
                    Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontFeatures: AppTheme.tabular,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(placeholderIcon, size: 22, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
