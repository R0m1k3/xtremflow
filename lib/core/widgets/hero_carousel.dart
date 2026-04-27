import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'glass_container.dart';
import 'tv_focusable_card.dart';

class HeroCarouselItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final List<String>? badges;

  HeroCarouselItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onPlay,
    this.badges,
  });
}

class HeroCarousel extends StatefulWidget {
  final List<HeroCarouselItem> items;
  final bool autoPlay;

  const HeroCarousel({
    super.key,
    required this.items,
    this.autoPlay = true,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.autoPlay) {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_currentIndex < widget.items.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 800),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String? _getProxiedUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) {
      return '/api/xtream/$url';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 560,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _buildHeroSlide(item);
            },
          ),

          // Indicators
          Positioned(
            bottom: 32,
            right: 48,
            child: Row(
              children: List.generate(
                widget.items.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentIndex == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentIndex == index
                        ? AppColors.primaryContainer
                        : Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSlide(HeroCarouselItem item) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Image
        if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
          Image.network(
            _getProxiedUrl(item.imageUrl)!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceContainerLow),
          )
        else
          Container(color: AppColors.surfaceContainerLow),

        // Gradient Overlays — Stitch style
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.baseLevel0.withOpacity(0.4),
                AppColors.baseLevel0.withOpacity(0.9),
                AppColors.baseLevel0,
              ],
              stops: const [0.0, 0.5, 0.8, 1.0],
            ),
          ),
        ),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [
                Colors.transparent,
                AppColors.baseLevel0.withOpacity(0.8),
              ],
            ),
          ),
        ),

        // Content Info
        Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badges row
              if (item.badges != null && item.badges!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    children: item.badges!.map((badge) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          badge.toUpperCase(),
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    'FEATURED',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Title
              SizedBox(
                width: 600,
                child: Text(
                  item.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    height: 1.1,
                    letterSpacing: -0.02,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.subtitle!,
                  style: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  TvFocusableCard(
                    onTap: item.onPlay,
                    borderRadius: 50,
                    scaleFactor: 1.1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryContainer.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: AppColors.onSurface,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'WATCH NOW',
                            style: GoogleFonts.inter(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  TvFocusableCard(
                    onTap: item.onTap,
                    borderRadius: 50,
                    child: GlassContainer.glass(
                      borderRadius: 50,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.onSurface,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'DETAILS',
                            style: GoogleFonts.inter(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );
  }
}
