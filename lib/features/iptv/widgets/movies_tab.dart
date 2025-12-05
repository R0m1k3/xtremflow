import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../screens/video_player_screen.dart';

class MoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const MoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<MoviesTab> {
  final ScrollController _scrollController = ScrollController();
  final List<Movie> _movies = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _loadMoreMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreMovies();
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
    if (_movies.isEmpty && !_isLoading) {
      return const Center(child: Text('No movies available'));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: _movies.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _movies.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final movie = _movies[index];
        return _MovieCard(
          movie: movie,
          playlist: widget.playlist,
        );
      },
    );
  }
}

class _MovieCard extends StatelessWidget {
  final Movie movie;
  final PlaylistConfig playlist;

  const _MovieCard({
    required this.movie,
    required this.playlist,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final streamUrl = movie.getStreamUrl(
            playlist.dns,
            playlist.username,
            playlist.password,
          );
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                streamUrl: streamUrl,
                title: movie.name,
                posterUrl: movie.streamIcon,
              ),
            ),
          );
        },
        child: Column(
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
      ),
    );
  }
}
