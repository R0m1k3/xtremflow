import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';

import '../../../../core/widgets/components/hero_carousel.dart';
import '../../../../core/widgets/components/ui_components.dart';
import '../../../../features/iptv/models/xtream_models.dart';
import '../../../../features/iptv/providers/xtream_provider.dart';
import '../../../../features/iptv/providers/settings_provider.dart';
import '../screens/mobile_series_detail_screen.dart';

class MobileSeriesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileSeriesTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileSeriesTab> createState() => _MobileSeriesTabState();
}

class _MobileSeriesTabState extends ConsumerState<MobileSeriesTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Series> _series = [];
  List<Series>? _searchResults;
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
    // Only trigger load when near bottom and not already loading
    if (!_isLoading && _hasMore &&
        _scrollController.position.pixels >=
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
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadMoreSeries() async {
    // Double-check conditions to prevent race conditions
    if (_isLoading || !_hasMore || !mounted) return;

    // Set loading flag immediately before any async operation
    _isLoading = true;
    if (mounted) setState(() {});

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final newSeries = await service.getSeriesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          _series.addAll(newSeries);
          _currentOffset += _pageSize;
          _hasMore = newSeries.length == _pageSize;
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
        builder: (context) => MobileSeriesDetailScreen(
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

    // Hero Items (use filtered series)
    final heroItems = displaySeries.take(3).map((s) => HeroItem(
      id: s.seriesId.toString(),
      title: s.name,
      imageUrl: _getProxiedImageUrl(s.cover),
      subtitle: s.rating != null ? '${_formatRating(s.rating)} ★' : null,
      onMoreInfo: () => _openSeries(s),
    )).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header & Search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Search Series',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(bottom: 11),
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
            ),
          ),

          // Hero Section
          if (_searchQuery.isEmpty && heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                   height: 250,
                   child: HeroCarousel(
                     items: heroItems,
                     onTap: (item) {
                       // Find series by title fallback if ID logic differs (Series ID is int usually, Hero is Str)
                       // But here we rely on passing the correct string ID or using the closure directly if possible.
                       // HeroCarousel onTap returns HeroItem. 
                       // We must map it back. 
                       try {
                         final series = _series.firstWhere((s) => s.seriesId.toString() == item.id);
                         _openSeries(series);
                       } catch (e) {
                         // Fallback logic not critical for now, assume ID matches
                       }
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
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= displaySeries.length) return null;
                  final series = displaySeries[index];
                  
                  return MediaCard(
                    title: series.name,
                    imageUrl: _getProxiedImageUrl(series.cover),

                    subtitle: series.rating != null ? '${_formatRating(series.rating)} ★' : null,
                    rating: _formatRating(series.rating),
                    placeholderIcon: Icons.tv,
                    onTap: () => _openSeries(series),
                  );
                },
                childCount: displaySeries.length,
              ),
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
