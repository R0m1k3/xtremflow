import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_config.dart';
import '../../../core/navigation/search_requests.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/hero_carousel.dart';

import '../models/xtream_models.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/series_detail_screen.dart';
import 'live_widgets.dart' show SectionTitle;
import 'movies_tab.dart' show PosterCard;

class SeriesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const SeriesTab({super.key, required this.playlist});

  @override
  ConsumerState<SeriesTab> createState() => _SeriesTabState();
}

class _SeriesTabState extends ConsumerState<SeriesTab> {
  static const _tabIndex = 2;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'series-search');
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

  /// « Rechercher » of the side rail, while Séries is on screen.
  void _onSearchRequest() {
    if (activeTab.value != _tabIndex || !mounted) return;
    _searchFocus.requestFocus();
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
          SnackBar(content: Text('Impossible de charger les séries : $e')),
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
        builder: (context) =>
            SeriesDetailScreen(series: series, playlist: widget.playlist),
      ),
    );
  }

  Series _resolve(Series s) => _series.firstWhere(
    (element) => element.seriesId.toString() == s.seriesId.toString(),
    orElse: () => s,
  );

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
          hintText: 'Rechercher une série',
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

    final bool showingResults =
        _searchQuery.isNotEmpty && _searchResults != null;
    List<Series> displaySeries;
    if (showingResults) {
      displaySeries = _searchResults!;
    } else {
      displaySeries = settings.seriesKeywords.isEmpty
          ? _series
          : _series
                .where((s) => settings.matchesSeriesFilter(s.categoryName))
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
                      'Séries',
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
          if (_searchQuery.isEmpty && displaySeries.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 6, 32, 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: HeroCarousel(
                    items: displaySeries
                        .take(5)
                        .map(
                          (s) => HeroCarouselItem(
                            id: s.seriesId.toString(),
                            title: s.name,
                            imageUrl: _getProxiedImageUrl(s.cover),
                            subtitle: s.rating != null
                                ? 'Note ${_formatRating(s.rating)}'
                                : null,
                            onPlay: () => _openSeries(_resolve(s)),
                            onTap: () => _openSeries(_resolve(s)),
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
                  ? SectionTitle('Résultats', count: displaySeries.length)
                  : const SectionTitle('Toutes les séries'),
            ),
          ),

          // Series grid
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
                    if (index >= displaySeries.length) return null;
                    final serie = displaySeries[index];
                    return PosterCard(
                      title: serie.name,
                      imageUrl: serie.cover != null && serie.cover!.isNotEmpty
                          ? _getProxiedImageUrl(serie.cover)
                          : null,
                      rating: _formatRating(serie.rating),
                      placeholderIcon: Icons.tv_rounded,
                      semanticLabel: 'Série ${serie.name}',
                      onPressed: () => _openSeries(serie),
                    );
                  }, childCount: displaySeries.length),
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
