import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/hero_carousel.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final List<Series> _series = [];
  List<Series>? _searchResults;
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
    _loadMoreSeries();
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
      _loadMoreSeries();
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
      final results = await service.searchSeries(query);

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

  void _openSeries(Series series) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SeriesDetailScreen(
          series: series,
          playlist: widget.playlist,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(iptvSettingsProvider);

    List<Series> displaySeries;
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      displaySeries = _searchResults!;
    } else {
      displaySeries = settings.seriesKeywords.isEmpty
          ? _series
          : _series
              .where((s) => settings.matchesSeriesFilter(s.categoryName))
              .toList();
    }

    const double gridItemRatio = 0.65;
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
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: GlassContainer(
                borderRadius: 100,
                opacity: 0.6,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'TV Series',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 300,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            size: 20,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search series...',
                                hintStyle:
                                    GoogleFonts.inter(color: Colors.white54),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.only(bottom: 12),
                              ),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          if (_isSearching)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Hero Carousel
          if (_searchQuery.isEmpty && displaySeries.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: HeroCarousel(
                  items: displaySeries
                      .take(5)
                      .map(
                        (s) => HeroCarouselItem(
                          id: s.seriesId.toString(),
                          title: s.name,
                          imageUrl: _getProxiedImageUrl(s.cover),
                          subtitle: s.rating != null
                              ? '${_formatRating(s.rating)} ★'
                              : null,
                          onPlay: () {
                            final series = _series.firstWhere(
                              (element) =>
                                  element.seriesId.toString() ==
                                  s.seriesId.toString(),
                              orElse: () => s,
                            );
                            _openSeries(series);
                          },
                          onTap: () {
                            final series = _series.firstWhere(
                              (element) =>
                                  element.seriesId.toString() ==
                                  s.seriesId.toString(),
                              orElse: () => s,
                            );
                            _openSeries(series);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),

          // Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: gridItemRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= displaySeries.length) return null;
                  final serie = displaySeries[index];
                  return TvFocusableCard(
                    onTap: () => _openSeries(serie),
                    borderRadius: 12,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Poster Image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: serie.cover != null && serie.cover!.isNotEmpty
                              ? Image.network(
                                  _getProxiedImageUrl(serie.cover),
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Center(
                                      child: Icon(
                                        Icons.tv,
                                        size: 48,
                                        color: Colors.white24,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Center(
                                    child: Icon(
                                      Icons.tv,
                                      size: 48,
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                        ),

                        // Gradient Overlay
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 80,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.9),
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        // Title
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Text(
                            serie.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                const Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Rating Badge
                        if (serie.rating != null && serie.rating!.isNotEmpty)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 10,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatRating(serie.rating)!,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                childCount: displaySeries.length,
              ),
            ),
          ),

          // Loader
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    );
  }
}
