import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/components/hero_carousel.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../features/iptv/providers/watch_history_provider.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../screens/mobile_player_screen.dart';

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
    if (!_isLoading && _hasMore &&
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

  String _getProxiedImageUrl(String? originalUrl) {
    if (originalUrl == null || originalUrl.isEmpty) return '';
    if (originalUrl.startsWith('http://')) {
      return '/api/xtream/$originalUrl';
    }
    return originalUrl;
  }

  void _playMovie(Movie movie) {
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
          : _movies.where((m) => settings.matchesMoviesFilter(m.categoryName)).toList();
    }

    final heroItems = displayMovies.take(3).map((m) => HeroItem(
      id: m.streamId,
      title: m.name,
      imageUrl: _getProxiedImageUrl(m.streamIcon),
      subtitle: m.rating != null ? '${_formatRating(m.rating)} ★' : null,
      onMoreInfo: () => _playMovie(m),
    )).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Glass Header & Search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlassContainer(
                borderRadius: 100,
                opacity: 0.1, // Glass
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: Colors.white54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search Movies...',
                          hintStyle: GoogleFonts.inter(color: Colors.white54),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.only(bottom: 11),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    if (_isSearching)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                           _searchController.clear();
                           _onSearchChanged('');
                        },
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                  ],
                ),
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
                       final movie = _movies.firstWhere((element) => element.streamId == item.id);
                       _playMovie(movie);
                     },
                   ),
                ),
              ),
            ),
          
          // Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= displayMovies.length) return null;
                  final movie = displayMovies[index];
                  final isWatched = watchHistory.isMovieWatched(movie.streamId);
                  
                  return GestureDetector(
                    onTap: () => _playMovie(movie),
                    onLongPress: () {
                       ref.read(watchHistoryProvider.notifier).toggleMovieWatched(movie.streamId);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Poster
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: movie.streamIcon != null && movie.streamIcon!.isNotEmpty
                            ? Image.network(
                                _getProxiedImageUrl(movie.streamIcon),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                              )
                            : Container(color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
                        ),
                        
                        // Gradient Overlay
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          height: 80,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                              ),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                            ),
                          ),
                        ),

                        // Title
                        Positioned(
                          bottom: 12, left: 12, right: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                movie.name,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isWatched)
                                Text('WATCHED', style: GoogleFonts.inter(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),

                        // Rating
                        if (movie.rating != null && movie.rating!.isNotEmpty)
                          Positioned(
                            top: 8, right: 8,
                            child: GlassContainer(
                              borderRadius: 4,
                              opacity: 0.6,
                              color: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, size: 10, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatRating(movie.rating)!,
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                childCount: displayMovies.length,
              ),
            ),
          ),
          
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
