import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Glassmorphism container with 3 depth levels (Stitch Design System)
///
/// Level 0: Pure base background (#0F1014), no blur.
/// Level 1: Translucent layer with backdrop blur 20px, 1px border 10% white.
/// Level 2: High-blur floating container with subtle inner glow in primary accent.
enum GlassLevel { level0, level1, level2 }

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final GlassLevel level;
  final Color? borderColor;
  final bool border;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 16.0,
    this.level = GlassLevel.level1,
    this.borderColor,
    this.border = true,
    this.boxShadow,
  });

  /// Convenience constructor for Level 0 (pure base)
  const GlassContainer.base({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 16.0,
    this.borderColor,
    this.border = false,
    this.boxShadow,
  }) : level = GlassLevel.level0;

  /// Convenience constructor for Level 1 (standard glass)
  const GlassContainer.glass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 16.0,
    this.borderColor,
    this.border = true,
    this.boxShadow,
  }) : level = GlassLevel.level1;

  /// Convenience constructor for Level 2 (floating with inner glow)
  const GlassContainer.floating({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 24.0,
    this.borderColor,
    this.border = true,
    this.boxShadow,
  }) : level = GlassLevel.level2;

  @override
  Widget build(BuildContext context) {
    switch (level) {
      case GlassLevel.level0:
        return _buildLevel0();
      case GlassLevel.level1:
        return _buildLevel1();
      case GlassLevel.level2:
        return _buildLevel2();
    }
  }

  Widget _buildLevel0() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.baseLevel0,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border
            ? Border.all(
                color: borderColor ?? Colors.transparent,
                width: 1,
              )
            : null,
      ),
      child: child,
    );
  }

  Widget _buildLevel1() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: AppColors.glassLevel1Bg,
              border: border
                  ? Border.all(
                      color: borderColor ?? AppColors.glassLevel1Border,
                      width: 1,
                    )
                  : null,
              boxShadow: boxShadow ??
                  [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildLevel2() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: AppColors.glassLevel2Bg,
              border: border
                  ? Border(
                      top: BorderSide(
                        color: borderColor ?? AppColors.glassLevel2InnerGlow,
                        width: 1,
                      ),
                      left: BorderSide(
                        color: borderColor ?? AppColors.glassLevel2InnerGlow,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: borderColor ?? AppColors.glassLevel2Border,
                        width: 1,
                      ),
                      bottom: BorderSide(
                        color: borderColor ?? AppColors.glassLevel2Border,
                        width: 1,
                      ),
                    )
                  : null,
              boxShadow: boxShadow ??
                  [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1),
                      blurRadius: 40,
                      spreadRadius: -10,
                    ),
                  ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
