import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class HeroCarouselItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final Color? accentColor;
  final String? badge;

  HeroCarouselItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onPlay,
    this.accentColor,
    this.badge,
  });
}

class HeroCarousel extends StatefulWidget {
  final List<HeroCarouselItem> items;
  final bool autoPlay;
  final Duration autoPlayInterval;
  final double height;

  const HeroCarousel({
    super.key,
    required this.items,
    this.autoPlay = true,
    this.autoPlayInterval = const Duration(seconds: 6),
    this.height = 360,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 1.0);

    // Starts visible: the first slide shows its title and buttons at once.
    _fadeController = AnimationController(
      vsync: this,
      duration: AppTheme.durationLg,
      value: 1.0,
    );

    if (widget.autoPlay && widget.items.isNotEmpty) {
      _startAutoPlay();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.autoPlayInterval, (timer) {
      if (mounted && widget.items.isNotEmpty && _pageController.hasClients) {
        final nextPage = (_currentIndex + 1) % widget.items.length;
        _pageController.animateToPage(
          nextPage,
          duration: AppTheme.durationLg,
          curve: AppTheme.curveSmooth,
        );
      }
    });
  }

  void _stopAutoPlay() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return SizedBox(height: widget.height);
    final current =
        widget.items[_currentIndex.clamp(0, widget.items.length - 1)];
    return MouseRegion(
      onEnter: (_) => _stopAutoPlay(),
      onExit: (_) {
        if (widget.autoPlay) {
          _startAutoPlay();
        }
      },
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  _fadeController.forward(from: 0.0);
                },
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  return _buildCarouselPage(widget.items[index]);
                },
              ),
            ),
            // Veil from the left so the title reads over any artwork.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroScrim),
              ),
            ),
            Positioned(
              bottom: 36,
              left: 40,
              right: 40,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: _buildContentOverlay(current),
                  ),
                ),
              ),
            ),
            if (widget.items.length > 1)
              Positioned(bottom: 24, right: 32, child: _buildIndicators()),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselPage(HeroCarouselItem item) {
    if (item.imageUrl == null || item.imageUrl!.isEmpty) {
      return const SizedBox.expand();
    }
    return Image.network(
      item.imageUrl!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      cacheWidth: 1280,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 56,
            color: AppColors.textMuted,
          ),
        );
      },
    );
  }

  Widget _buildContentOverlay(HeroCarouselItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.badge != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accentFill,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              item.badge!,
              style: AppTheme.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: item.accentColor ?? AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.display(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        if (item.subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            item.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              fontSize: 16,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
        if (item.onPlay != null || item.onTap != null) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              if (item.onPlay != null)
                FilledButton.icon(
                  onPressed: item.onPlay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Lire'),
                ),
              if (item.onPlay != null && item.onTap != null)
                const SizedBox(width: 12),
              if (item.onTap != null)
                OutlinedButton.icon(
                  onPressed: item.onTap,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                  label: const Text("Plus d'infos"),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        widget.items.length,
        (index) => GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: AppTheme.durationMd,
              curve: AppTheme.curveDefault,
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: AppTheme.durationMd,
              curve: AppTheme.curveDefault,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentIndex == index ? 24 : 8,
              height: 6,
              decoration: BoxDecoration(
                color: _currentIndex == index
                    ? AppColors.textPrimary
                    : AppColors.onSurface38,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
