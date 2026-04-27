import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../glass_container.dart';

/// Stitch-style glass card using GlassContainer Level 1.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool showBorder;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 12,
    this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer.glass(
      borderRadius: borderRadius,
      border: showBorder,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated gradient primary button with Stitch glow.
class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isExpanded;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isExpanded = false,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: AppTheme.curveDefault),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: [
            BoxShadow(
              color: AppColors.glowPrimary(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.glowPrimary(0.1),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onPressed,
            onTapDown: (_) => _controller.forward(),
            onTapUp: (_) => _controller.reverse(),
            onTapCancel: () => _controller.reverse(),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onSurface,
                      ),
                    )
                  : Row(
                      mainAxisSize: widget.isExpanded
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: AppColors.onSurface, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          style: GoogleFonts.inter(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 0.05,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return widget.isExpanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Shimmer loading effect using surface container tones.
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [
                AppColors.surfaceContainerLow.withOpacity(0.5),
                AppColors.surfaceContainer,
                AppColors.surfaceContainerLow.withOpacity(0.5),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Live indicator badge — Stitch style pill.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 6, color: AppColors.onSurface),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: GoogleFonts.inter(
              color: AppColors.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch-style category chip — pill shaped with primary accent.
class CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppColors.primary.withOpacity(0.1)
          : AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.3)
                  : AppColors.outlineVariant,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Media poster card with Stitch glass hover effect.
class MediaCard extends StatefulWidget {
  final String title;
  final String? imageUrl;
  final String? subtitle;
  final String? rating;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isWatched;
  final IconData placeholderIcon;

  const MediaCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.rating,
    this.onTap,
    this.onLongPress,
    this.isWatched = false,
    this.placeholderIcon = Icons.movie,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final focusBorderColor =
        _isHovered ? AppColors.primaryContainer.withOpacity(0.5) : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Poster Image
            Expanded(
              child: AnimatedScale(
                scale: _isHovered ? 1.05 : 1.0,
                duration: AppTheme.durationFast,
                curve: AppTheme.curveDefault,
                child: AnimatedContainer(
                  duration: AppTheme.durationFast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    color: AppColors.surfaceContainerLow,
                    border: Border.all(
                      color: focusBorderColor,
                      width: _isHovered ? 2 : 0,
                    ),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: AppColors.glowPrimary(0.3),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: AppColors.glowPrimary(0.1),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        AppTheme.radiusMd - (_isHovered ? 2 : 0)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: widget.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surfaceContainerLow,
                              child: Center(
                                child: Icon(widget.placeholderIcon,
                                    color: AppColors.outline),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surfaceContainerLow,
                              child: Center(
                                child: Icon(widget.placeholderIcon,
                                    color: AppColors.outline),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: AppColors.surfaceContainerLow,
                            child: Center(
                              child: Icon(widget.placeholderIcon,
                                  color: AppColors.outline),
                            ),
                          ),

                        // Rating Badge (Top Left)
                        if (widget.rating != null &&
                            widget.rating!.isNotEmpty)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star,
                                      size: 10, color: AppColors.primaryContainer),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.rating!,
                                    style: GoogleFonts.inter(
                                      color: AppColors.onSurface,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Watched Indicator (Top Right)
                        if (widget.isWatched)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  size: 12, color: AppColors.onSurface),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Title & Subtitle (Below)
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _isHovered
                          ? AppColors.primary
                          : AppColors.onSurface,
                      fontWeight:
                          _isHovered ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (widget.subtitle != null && _isHovered) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 11,
                      ),
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
