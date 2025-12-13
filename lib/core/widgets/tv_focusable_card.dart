import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TvFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final double scaleFactor;
  final Duration animationDuration;
  final Color? focusColor;
  final bool autofocus;
  final double borderRadius;

  const TvFocusableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onFocus,
    this.scaleFactor = 1.05,
    this.animationDuration = const Duration(milliseconds: 200),
    this.focusColor,
    this.autofocus = false,
    this.borderRadius = 12.0,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleFactor)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (widget.onFocus != null && hasFocus) {
      widget.onFocus!();
    }
    setState(() {
      _isFocused = hasFocus;
    });
    if (hasFocus) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: _handleFocusChange,
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        focusColor: Colors.transparent, // We handle visual focus manually
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: _isFocused
                ? Border.all(
                    color: widget.focusColor ?? AppColors.focusBorder,
                    width: 3,
                  )
                : Border.all(color: Colors.transparent, width: 3),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: (widget.focusColor ?? AppColors.focusBorder).withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
