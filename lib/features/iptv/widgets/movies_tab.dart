import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';
import '../screens/player_screen.dart';

class MoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const MoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<MoviesTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Movie> _movies = [];
  List<Movie>? _searchResults; // Results from full catalog search
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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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
      final newMovies = await service.getMovies(
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
          SnackBar(content: Text('Failed to load movies: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);
    
    // Use search results if searching, otherwise use loaded movies with category filter
    List<Movie> displayMovies;
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      displayMovies = _searchResults!;
    } else {
      displayMovies = settings.moviesKeywords.isEmpty
          ? _movies
          : _movies.where((m) => settings.matchesMoviesFilter(m.categoryName)).toList();
    }

    if (_movies.isEmpty && !_isLoading) {
      return const Center(child: Text('No movies available'));
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search all movies...',
              hintStyle: GoogleFonts.roboto(color: Colors.grey.shade500),
              prefixIcon: _isSearching 
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey.shade800,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: GoogleFonts.roboto(color: Colors.white),
            onChanged: _onSearchChanged,
          ),
        ),
        
        // Results count
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${displayMovies.length} result${displayMovies.length != 1 ? 's' : ''} found',
                style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
        
        // Movie grid
        Expanded(
          child: displayMovies.isEmpty && _movies.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isNotEmpty ? Icons.search_off : Icons.filter_list_off,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty 
                            ? 'No movies match "$_searchQuery"'
                            : 'No movies match the filter',
                        style: GoogleFonts.roboto(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.65,
                  ),
                  itemCount: displayMovies.length + (_hasMore && _searchQuery.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= displayMovies.length) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final movie = displayMovies[index];
                    return _MovieCard(
                      movie: movie,
                      playlist: widget.playlist,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MovieCard extends ConsumerWidget {
  final Movie movie;
  final PlaylistConfig playlist;

  const _MovieCard({
    required this.movie,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchHistory = ref.watch(watchHistoryProvider);
    final isWatched = watchHistory.isMovieWatched(movie.streamId);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Mark as watched when opening
          ref.read(watchHistoryProvider.notifier).markMovieWatched(movie.streamId);
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayerScreen(
                streamId: movie.streamId,
                title: movie.name,
                playlist: playlist,
                streamType: StreamType.vod,
                containerExtension: movie.containerExtension ?? 'mp4',
              ),
            ),
          );
        },
        onLongPress: () {
          // Toggle watched status on long press
          ref.read(watchHistoryProvider.notifier).toggleMovieWatched(movie.streamId);
        },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: movie.streamIcon != null
                      ? CachedNetworkImage(
                          imageUrl: movie.streamIcon!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade800,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade800,
                            child: const Icon(Icons.movie, size: 48),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.movie, size: 48),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.name,
                        style: GoogleFonts.roboto(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (movie.rating != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              movie.rating!,
                              style: GoogleFonts.roboto(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Watched indicator
            if (isWatched)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
