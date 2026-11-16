import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../glass_container.dart';
import '../tv_focusable.dart';

/// Glass card ([GlassDecoration]). With [onTap] it is focusable: the lit
/// card on focus (hover on the web). [showBorder] is kept for older call
/// sites and ignored (the glass draws its own rim).
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
    if (onTap == null) {
      return GlassContainer(
        borderRadius: borderRadius,
        padding: padding,
        child: child,
      );
    }
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.03,
      borderRadius: BorderRadius.circular(borderRadius),
      onPressed: onTap,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: padding,
            decoration: GlassDecoration(
              lit: lit ? 1 : 0,
              radius: borderRadius,
              halo: false,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                color: lit ? AppColors.onFocus : AppColors.textSecondary,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Primary button. The name is kept from the former gradient button; it is
/// now the theme's [FilledButton]: the lit surface with dark ink.
class GradientButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textMuted,
              ),
            )
          : Row(
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTheme.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onFocus,
                  ),
                ),
              ],
            ),
    );

    return isExpanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Loading placeholder: a graphite block that breathes between two surface
/// steps (no moving gradient).
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: Color.lerp(
              AppColors.shimmer,
              AppColors.shimmerHighlight,
              _controller.value,
            ),
          ),
        );
      },
    );
  }
}

/// « En direct » pill (sentence case, accent; red is kept for the progress
/// of the programme on now).
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'En direct',
        style: AppTheme.body(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

/// Category pill: accent tint when selected, lit on focus.
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
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.04,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      onPressed: onTap,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: lit
                  ? AppColors.focus
                  : (isSelected ? AppColors.accentFill : AppColors.surface),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Text(
              label,
              style: AppTheme.body(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: lit
                    ? AppColors.onFocus
                    : (isSelected ? AppColors.accent : AppColors.textSecondary),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Poster card: the poster grows and gets a light edge on focus (hover on
/// the web), the title under it lights up. No shadow, no glow.
class MediaCard extends StatelessWidget {
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

  Widget _placeholder() => Container(
    color: AppColors.surfaceHigh,
    child: Center(child: Icon(placeholderIcon, color: AppColors.textMuted)),
  );

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.0,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onPressed: onTap,
      onLongPress: onLongPress,
      longPressDuration: const Duration(milliseconds: 700),
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Poster Image
              Expanded(
                child: AnimatedScale(
                  scale: lit ? 1.05 : 1.0,
                  duration: AppTheme.durationFocus,
                  curve: AppTheme.curveFocus,
                  child: AnimatedContainer(
                    duration: AppTheme.durationFocus,
                    curve: AppTheme.curveFocus,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      color: lit ? AppColors.focus : AppColors.surface,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusMd - 2,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imageUrl != null)
                            CachedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 400,
                              placeholder: (context, url) => _placeholder(),
                              errorWidget: (context, url, error) =>
                                  _placeholder(),
                            )
                          else
                            _placeholder(),

                          // Rating Badge (Top Left)
                          if (rating != null && rating!.isNotEmpty)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                // Scrim over the poster: legible on any image.
                                decoration: BoxDecoration(
                                  color: AppColors.rail.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      size: 11,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating!,
                                      style: AppTheme.body(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: AppTheme.tabular,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Watched Indicator (Top Right)
                          if (isWatched)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: AppColors.onFocus,
                                ),
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
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: lit
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (subtitle != null && lit) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
