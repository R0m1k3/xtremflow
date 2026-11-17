import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class HeroCarousel extends StatefulWidget {
  final List<HeroItem> items;
  final Function(HeroItem) onTap;

  const HeroCarousel({super.key, required this.items, required this.onTap});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.9);
    _startAutoPlay();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stopAutoPlay();
    super.dispose();
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_currentPage < widget.items.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  void _stopAutoPlay() {
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 400,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentPage = index);
        },
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final isActive = index == _currentPage;

          return AnimatedScale(
            duration: const Duration(milliseconds: 500),
            scale: isActive ? 1.0 : 0.94,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: isActive ? 1.0 : 0.5,
              child: GestureDetector(
                onTap: () => widget.onTap(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background image
                      CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        memCacheWidth: 1280,
                        placeholder: (context, url) =>
                            const ColoredBox(color: AppColors.surface),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 56,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),

                      // Veil from the left so the title reads over the art.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroScrim,
                        ),
                      ),

                      // Content
                      Positioned(
                        bottom: 28,
                        left: 28,
                        right: 28,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: AppTheme.display(
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                item.subtitle!,
                                style: AppTheme.body(
                                  fontSize: 15,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => widget.onTap(item),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 22,
                              ),
                              label: const Text('Lire'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HeroItem {
  final String id;
  final String title;
  final String imageUrl;
  final String? subtitle;
  final VoidCallback? onMoreInfo;

  HeroItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.subtitle,
    this.onMoreInfo,
  });
}
