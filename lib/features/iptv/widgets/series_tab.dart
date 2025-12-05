import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../services/xtream_service.dart';
import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';

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
    if (_series.isEmpty && !_isLoading) {
      return const Center(child: Text('No series available'));
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
      itemCount: _series.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _series.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final serie = _series[index];
        return _SeriesCard(series: serie);
      },
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final Series series;

  const _SeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Series require episode selection screen (not implemented)
          // For now, show info dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(series.name),
              content: const Text(
                'Series playback requires episode selection.\n\n'
                'Use Xtream API endpoint get_series_info to fetch episodes.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
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
