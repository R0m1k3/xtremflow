import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  int _currentIndex = 0;
  Timer? _timer;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 1.0,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: AppTheme.durationLg,
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: AppTheme.durationXl,
    )..repeat(reverse: true);

    if (widget.autoPlay && widget.items.isNotEmpty) {
      _startAutoPlay();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(widget.autoPlayInterval, (timer) {
      if (mounted) {
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
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _stopAutoPlay();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        if (widget.autoPlay) {
          _startAutoPlay();
        }
      },
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
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
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.background.withOpacity(0.6),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 32,
              right: 32,
              child: FadeTransition(
                opacity: _fadeController,
                child: _buildContentOverlay(widget.items[_currentIndex]),
              ),
            ),
            Positioned(
              bottom: 20,
              right: 32,
              child: _buildIndicators(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselPage(HeroCarouselItem item) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
          Image.network(
            item.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppColors.surface,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 64),
                ),
              );
            },
          )
        else
          Container(color: AppColors.surface),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withOpacity(0.3),
                AppColors.background.withOpacity(0.8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentOverlay(HeroCarouselItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: item.accentColor ?? AppColors.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              item.badge!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -1.0,
            height: 1.1,
          ),
        ),
        if (item.subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            item.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (item.onPlay != null || item.onTap != null)
          Row(
            children: [
              if (item.onPlay != null)
                AnimatedScale(
                  scale: _isHovered ? 1.05 : 1.0,
                  duration: AppTheme.durationMd,
                  child: GestureDetector(
                    onTap: item.onPlay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: (item.accentColor ?? AppColors.primary)
                                .withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow,
                              color: AppColors.textPrimary),
                          const SizedBox(width: 8),
                          Text(
                            'Play',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 16),
              if (item.onTap != null)
                GestureDetector(
                  onTap: item.onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.8),
                      border: Border.all(
                        color: AppColors.border,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'More Info',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
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
          child: AnimatedContainer(
            duration: AppTheme.durationMd,
            curve: AppTheme.curveDefault,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: _currentIndex == index ? 32 : 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  _currentIndex == index ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
