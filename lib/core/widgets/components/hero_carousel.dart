
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class HeroCarousel extends StatefulWidget {
  final List<HeroItem> items;
  final Function(HeroItem) onTap;

  const HeroCarousel({
    super.key,
    required this.items,
    required this.onTap,
  });

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
            scale: isActive ? 1.0 : 0.9,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: isActive ? 1.0 : 0.5,
              child: GestureDetector(
                onTap: () => widget.onTap(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    boxShadow: [
                      if (isActive)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Image
                        CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: AppColors.surfaceVariant),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.surfaceVariant,
                            child: const Icon(Icons.movie, size: 64, color: AppColors.textTertiary),
                          ),
                        ),
                        
                        // Gradient Overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.2),
                                Colors.black.withOpacity(0.9),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                        
                        // Content
                        Positioned(
                          bottom: 32,
                          left: 32,
                          right: 32,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: GoogleFonts.outfit(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.subtitle != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.subtitle!,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _HeroButton(
                                    icon: Icons.play_arrow,
                                    label: 'Lecture',
                                    onPressed: () => widget.onTap(item),
                                    isPrimary: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class _HeroButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isPrimary,
  });

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_isHovered ? Colors.white : Colors.white.withOpacity(0.9))
                : (_isHovered ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: widget.isPrimary ? Colors.black : Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: widget.isPrimary ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
