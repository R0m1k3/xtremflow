import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_config.dart';
import '../../../core/navigation/search_requests.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/hero_carousel.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../providers/playback_positions_provider.dart';
import '../providers/watch_history_provider.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/player_screen.dart';
import 'live_widgets.dart' show SectionTitle;

class MoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const MoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<MoviesTab> {
  static const _tabIndex = 1;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'movies-search');
  final List<Movie> _movies = [];
  List<Movie>? _searchResults;
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 100;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMoreMovies();
    _scrollController.addListener(_onScroll);
    searchRequests.addListener(_onSearchRequest);
  }

  @override
  void dispose() {
    searchRequests.removeListener(_onSearchRequest);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// « Rechercher » of the side rail, while Films is on screen.
  void _onSearchRequest() {
    if (activeTab.value != _tabIndex || !mounted) return;
    _searchFocus.requestFocus();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
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
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final newMovies = await service.getMoviesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      );

      setState(() {
        _movies.addAll(newMovies);
        _currentOffset += _pageSize;
        _hasMore = newMovies.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de charger les films : $e')),
        );
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

  String _getProxiedImageUrl(String? originalUrl) {
    if (originalUrl == null || originalUrl.isEmpty) return '';
    if (originalUrl.startsWith('http://')) {
      return '/api/xtream/$originalUrl';
    }
    return originalUrl;
  }

  Future<void> _playMovie(Movie movie) async {
    ref.read(watchHistoryProvider.notifier).markMovieWatched(movie.streamId);

    Duration? movieDuration;
    if (movie.durationSecs != null && movie.durationSecs! > 0) {
      movieDuration = Duration(seconds: movie.durationSecs!);
    } else {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final durationSecs = await service.getVodDuration(movie.streamId);
      if (durationSecs != null && durationSecs > 0) {
        movieDuration = Duration(seconds: durationSecs);
      }
    }

    if (!mounted) return;

    // Reprise de lecture : les positions étaient sauvegardées par le player
    // mais jamais relues — le film repartait systématiquement de zéro.
    final positions = ref.read(playbackPositionsProvider);
    final resumeAt = positions.hasPosition(movie.streamId)
        ? positions.getPosition(movie.streamId)
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamId: movie.streamId,
          title: movie.name,
          playlist: widget.playlist,
          streamType: StreamType.vod,
          containerExtension: movie.containerExtension ?? 'mp4',
          duration: movieDuration,
          startTime: resumeAt,
        ),
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      width: 340,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        cursorColor: AppColors.accent,
        style: AppTheme.body(fontSize: 15),
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher un film',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);
    final watchHistory = ref.watch(watchHistoryProvider);

    final bool showingResults =
        _searchQuery.isNotEmpty && _searchResults != null;
    List<Movie> displayMovies;
    if (showingResults) {
      displayMovies = _searchResults!;
    } else {
      displayMovies = settings.moviesKeywords.isEmpty
          ? _movies
          : _movies
                .where((m) => settings.matchesMoviesFilter(m.categoryName))
                .toList();
    }

    final int crossAxisCount = ResponsiveLayout.value(
      context,
      mobile: 3,
      tablet: 5,
      desktop: 7,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header: title and search field
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Films',
                      style: AppTheme.display(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _searchField(),
                ],
              ),
            ),
          ),

          // Hero carousel (only when not searching)
          if (_searchQuery.isEmpty && displayMovies.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 6, 32, 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: HeroCarousel(
                    items: displayMovies
                        .take(5)
                        .map(
                          (m) => HeroCarouselItem(
                            id: m.streamId,
                            title: m.name,
                            imageUrl: _getProxiedImageUrl(m.streamIcon),
                            subtitle: m.rating != null
                                ? 'Note ${_formatRating(m.rating)}'
                                : null,
                            onPlay: () => _playMovie(m),
                            onTap: () => _playMovie(m),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 14),
            sliver: SliverToBoxAdapter(
              child: showingResults
                  ? SectionTitle('Résultats', count: displayMovies.length)
                  : const SectionTitle('Tous les films'),
            ),
          ),

          // Movies grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const spacing = 20.0;
                final tileWidth =
                    (constraints.crossAxisExtent -
                        spacing * (crossAxisCount - 1)) /
                    crossAxisCount;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    mainAxisExtent: PosterCard.extentFor(tileWidth),
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= displayMovies.length) return null;
                    final movie = displayMovies[index];
                    return PosterCard(
                      title: movie.name,
                      imageUrl:
                          movie.streamIcon != null &&
                              movie.streamIcon!.isNotEmpty
                          ? _getProxiedImageUrl(movie.streamIcon)
                          : null,
                      rating: _formatRating(movie.rating),
                      watched: watchHistory.isMovieWatched(movie.streamId),
                      placeholderIcon: Icons.movie_outlined,
                      semanticLabel: 'Film ${movie.name}',
                      onPressed: () => _playMovie(movie),
                    );
                  }, childCount: displayMovies.length),
                );
              },
            ),
          ),

          // Loader
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    );
  }
}

/// Poster of the Films and Séries grids: a glass card holding the 2:3
/// artwork, the title (two lines at most) and the rating under it. Lit when
/// focused or hovered.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onPressed,
    this.rating,
    this.watched = false,
    this.placeholderIcon = Icons.movie_outlined,
    this.semanticLabel,
  });

  final String title;
  final String? imageUrl;
  final String? rating;
  final bool watched;
  final IconData placeholderIcon;
  final String? semanticLabel;
  final VoidCallback onPressed;

  static const double _padding = 8;
  static const double _captionHeight = 64;
  static const double _radius = 14;

  /// Height of a card [width] wide.
  static double extentFor(double width) =>
      (width - 2 * _padding) * 3 / 2 + _captionHeight + 2 * _padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: TVFocusable(
        paintsOwnFocus: true,
        borderRadius: BorderRadius.circular(_radius),
        onPressed: onPressed,
        child: Builder(
          builder: (context) {
            final lit = TVFocusable.isFocused(context);
            final secondary = lit
                ? AppColors.onFocusMuted
                : AppColors.textSecondary;
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              padding: const EdgeInsets.all(_padding),
              decoration: GlassDecoration(lit: lit ? 1 : 0, radius: _radius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColoredBox(
                        color: AppColors.surfaceHigh,
                        child: imageUrl == null
                            ? _placeholder()
                            : Image.network(
                                imageUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 400,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (ctx, err, stack) =>
                                    _placeholder(),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _captionHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: lit
                                  ? AppColors.onFocus
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (rating != null) ...[
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: secondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  rating!,
                                  style: AppTheme.body(
                                    fontSize: 13,
                                    color: secondary,
                                    fontFeatures: AppTheme.tabular,
                                  ),
                                ),
                              ],
                              if (rating != null && watched)
                                Text(
                                  '  ·  ',
                                  style: AppTheme.body(
                                    fontSize: 13,
                                    color: secondary,
                                  ),
                                ),
                              if (watched)
                                Text(
                                  'Vu',
                                  style: AppTheme.body(
                                    fontSize: 13,
                                    color: lit
                                        ? AppColors.accentOnLight
                                        : AppColors.accent,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(placeholderIcon, size: 40, color: AppColors.textMuted),
    );
  }
}
