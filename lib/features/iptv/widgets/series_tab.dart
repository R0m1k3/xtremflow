import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../core/widgets/components/hero_carousel.dart';
import '../../../core/widgets/components/ui_components.dart';
import '../../../core/widgets/themed_loading_screen.dart';

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

  /// Proxy HTTP images through backend to avoid CORS/mixed-content issues
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
          : _series.where((s) => settings.matchesSeriesFilter(s.categoryName)).toList();
    }

    if (_series.isEmpty && !_isLoading) {
      return const Center(child: Text('No series available'));
    }

    // Hero Items
    final heroItems = displaySeries.take(5).map((s) => HeroItem(
      id: s.seriesId.toString(), // ID logic might differ for Series
      title: s.name,
      imageUrl: _getProxiedImageUrl(s.cover),
      subtitle: s.rating != null ? '${_formatRating(s.rating)} ★' : null,
      onMoreInfo: () => _openSeries(s),
    )).toList();

    final double gridItemRatio = 0.65;
    final int crossAxisCount = ResponsiveLayout.value(
      context,
      mobile: 3,
      tablet: 5,
      desktop: 7,
    );

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Text(
                  'TV Series',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 300,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 14, color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Rechercher...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.only(bottom: 12),
                            isDense: true,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      if (_isSearching)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                             _searchController.clear();
                             _onSearchChanged('');
                          },
                          child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Hero Carousel
        if (_searchQuery.isEmpty && heroItems.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: HeroCarousel(
                items: heroItems,
                onTap: (item) {
                   final series = _series.firstWhere((s) => s.name == item.title); // Fallback by title if ID mismatch
                   _openSeries(series);
                },
              ),
            ),
          ),
        
        // Grid
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 24,
              mainAxisSpacing: 32,
              childAspectRatio: gridItemRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= displaySeries.length) return null;
                final serie = displaySeries[index];
                return MediaCard(
                  title: serie.name,
                  imageUrl: _getProxiedImageUrl(serie.cover),

                  subtitle: serie.rating != null ? '${_formatRating(serie.rating)} ★' : null,
                  rating: _formatRating(serie.rating),
                  placeholderIcon: Icons.tv,
                  onTap: () => _openSeries(serie),
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
              padding: EdgeInsets.all(24),
              child: ThemedLoading(),
            ),
          ),
      ],
    );
  }
}
