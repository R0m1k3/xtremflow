import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Modern Apple TV Glass Container
///
/// Sophisticated glassmorphism with premium blur effects,
/// configurable transparency, and elegant borders.
///
/// Features:
/// - Backdrop blur (iOS-style glass effect)
/// - Subtle gradient overlay
/// - Premium border styling
/// - Shadow system
/// - Smooth animations
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? opacity;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool hasBorder;
  final double borderWidth;
  final bool showShadow;
  final double blur;
  final bool showGradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 16.0,
    this.opacity,
    this.backgroundColor,
    this.borderColor,
    this.hasBorder = true,
    this.borderWidth = 1.0,
    this.showShadow = true,
    this.blur = 15.0,
    this.showGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finalOpacity = opacity ?? 0.08;
    final finalBgColor = backgroundColor ?? AppColors.glassBackground;
    final finalBorderColor = borderColor ?? AppColors.glassBorder;

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              // Subtle gradient overlay for depth
              gradient: showGradient
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        finalBgColor.withOpacity(finalOpacity * 1.2),
                        finalBgColor.withOpacity(finalOpacity * 0.6),
                      ],
                    )
                  : null,
              border: hasBorder
                  ? Border.all(
                      color: finalBorderColor,
                      width: borderWidth,
                    )
                  : null,
              // Premium shadow
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        spreadRadius: -3,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Premium Glass Card - Full-featured variant
class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool interactive;
  final bool isLoading;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 16.0,
    this.interactive = false,
    this.isLoading = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTheme.durationMd,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
        CurvedAnimation(parent: _controller, curve: AppTheme.curveDefault));

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
        CurvedAnimation(parent: _controller, curve: AppTheme.curveDefault));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.interactive && widget.onTap != null) {
      _controller.forward();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = GlassContainer(
      borderRadius: widget.borderRadius,
      padding: widget.padding,
      margin: widget.margin,
      child: widget.child,
    );

    if (widget.interactive && widget.onTap != null) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _onPointerDown(
            const PointerDownEvent(
              position: Offset.zero,
            ),
          ),
          onTapUp: (_) => _onPointerUp(
            const PointerUpEvent(
              position: Offset.zero,
            ),
          ),
          onTapCancel: () => _controller.reverse(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: content,
            ),
          ),
        ),
      );
    }

    if (widget.isLoading) {
      content = Stack(
        children: [
          Opacity(opacity: 0.5, child: content),
          const Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }
}
