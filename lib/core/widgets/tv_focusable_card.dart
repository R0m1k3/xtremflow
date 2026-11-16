import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'tv_focusable.dart';

/// Focusable card of the « Salle obscure » charter.
///
/// Keeps the API of the former card and delegates to [TVFocusable]: the
/// mouse and the keyboard share one focus, and the focused card turns into
/// the lit glass pane ([GlassDecoration] with `lit: 1`). The child can read
/// [TVFocusable.isFocused] to switch its ink to [AppColors.onFocus].
class TvFocusableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final double scaleFactor;
  final Duration animationDuration;

  /// Kept for the callers; the charter has a single focus colour.
  final Color? focusColor;
  final bool autofocus;
  final double borderRadius;

  /// Accessibility label announced by screen readers (e.g. channel title).
  final String? semanticLabel;

  const TvFocusableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onFocus,
    this.scaleFactor = 1.03,
    this.animationDuration = AppTheme.durationFocus,
    this.focusColor,
    this.autofocus = false,
    this.borderRadius = 12.0,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: TVFocusable(
        onPressed: onTap,
        onFocus: onFocus,
        autofocus: autofocus,
        scale: scaleFactor,
        paintsOwnFocus: true,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Builder(
          builder: (ctx) => AnimatedContainer(
            duration: animationDuration,
            curve: AppTheme.curveFocus,
            decoration: GlassDecoration(
              lit: TVFocusable.isFocused(ctx) ? 1 : 0,
              radius: borderRadius,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
