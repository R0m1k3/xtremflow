import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/series_detail_screen.dart';

class SeriesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const SeriesTab({super.key, required this.playlist});

  @override
  ConsumerState<SeriesTab> createState() => _SeriesTabState();
}

class _SeriesTabState extends ConsumerState<SeriesTab> {
  final ScrollController _scrollController = ScrollController();
  final List<Series> _series = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _loadMoreSeries();
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
      _loadMoreSeries();
    }
  }

  Future<void> _loadMoreSeries() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final newSeries = await service.getSeriesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      );

      setState(() {
        _series.addAll(newSeries);
        _currentOffset += _pageSize;
        _hasMore = newSeries.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load series: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);
    
    // Filter series by category
    final filteredSeries = settings.seriesKeywords.isEmpty
        ? _series
        : _series.where((s) => settings.matchesSeriesFilter(s.categoryName)).toList();

    if (_series.isEmpty && !_isLoading) {
      return const Center(child: Text('No series available'));
    }

    if (filteredSeries.isEmpty && _series.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.filter_list_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No series match the filter',
              style: GoogleFonts.roboto(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Filter: ${settings.seriesCategoryFilter}',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.65,
      ),
      itemCount: filteredSeries.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= filteredSeries.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final serie = filteredSeries[index];
        return _SeriesCard(series: serie, playlist: widget.playlist);
      },
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final Series series;
  final PlaylistConfig playlist;

  const _SeriesCard({required this.series, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Navigate to series detail screen for episode selection
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SeriesDetailScreen(
                series: series,
                playlist: playlist,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: series.cover != null
                  ? CachedNetworkImage(
                      imageUrl: series.cover!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade800,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.tv, size: 48),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.tv, size: 48),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.name,
                    style: GoogleFonts.roboto(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (series.rating != null) ...[
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
                          series.rating!,
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
