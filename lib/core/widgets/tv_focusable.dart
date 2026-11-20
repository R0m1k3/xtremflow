import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/core/theme/app_theme.dart';

/// Remote-control focus. One focus state across the app: the focused item is
/// the only lit thing on screen — a slight scale-up and a neutral shadow.
///
/// * Default: a light outline is drawn around the child (screens that were
///   not redesigned rely on it).
/// * [paintsOwnFocus]: no outline; the child reads [TVFocusable.isFocused]
///   and turns itself into the lit surface (cards, rows).
///
/// Web: the mouse drives the same focus. Hovering an item focuses it, so a
/// single item is lit whether it is reached by the mouse or the keyboard.
/// Two rules: hovering never steals the focus from a text field, and a focus
/// that comes from the pointer does not scroll the list (a row near the edge
/// would slide under the cursor and the list would scroll by itself).
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double borderWidth;
  final Color focusColor;
  final BorderRadius? borderRadius;
  final Duration longPressDuration;

  /// The child draws the focused look itself (see [TVFocusable.isFocused]).
  final bool paintsOwnFocus;

  /// Whether the nearest enclosing [TVFocusable] has focus.
  static bool isFocused(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TVFocusScope>()?.focused ??
      false;

  const TVFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onFocus,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.05,
    this.borderWidth = 3.0,
    this.focusColor = AppColors.focus,
    this.borderRadius,
    this.longPressDuration = const Duration(seconds: 3),
    this.paintsOwnFocus = false,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  late FocusNode _node;
  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _isKeyDown = false;
  bool _longPressTriggered = false;

  /// The next focus change comes from the pointer: no scroll.
  bool _fromPointer = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_onFocusChanged);
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (_node.hasFocus != _isFocused) {
      setState(() => _isFocused = _node.hasFocus);
      if (_isFocused) {
        widget.onFocus?.call();
        if (!_fromPointer) _scrollToVisible();
      }
    }
    _fromPointer = false;
  }

  void _onHover(PointerEnterEvent event) {
    if (_node.hasFocus || !_node.canRequestFocus) return;
    if (_textFieldHasFocus()) return;
    _fromPointer = true;
    _node.requestFocus();
  }

  static bool _textFieldHasFocus() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Scrolls only when the item is cut or too close to an edge, and only by
  /// what is needed. Centring every item made the whole page slide (and
  /// redraw) on each press of the remote.
  void _scrollToVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro = context.findRenderObject();
      final scrollable = Scrollable.maybeOf(context);
      if (ro == null || !ro.attached || scrollable == null) return;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) return;
      final pos = scrollable.position;
      if (!pos.hasContentDimensions || !pos.hasViewportDimension) return;
      // Offsets that put the item at the leading / trailing edge.
      final lead = viewport.getOffsetToReveal(ro, 0).offset;
      final trail = viewport.getOffsetToReveal(ro, 1).offset;
      // Keep some of the neighbours in sight (and room for the lit halo).
      final margin = pos.viewportDimension * .12;
      double? target;
      if (pos.pixels > lead - margin) {
        target = lead - margin;
      } else if (pos.pixels < trail + margin) {
        target = trail + margin;
      }
      if (target == null) return;
      target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((target - pos.pixels).abs() < 1) return;
      pos.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handlePress() {
    widget.onPressed?.call();
  }

  void _handleLongPress() {
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        final isSelectKey =
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.numpadEnter;

        if (event is KeyDownEvent && isSelectKey) {
          if (!_isKeyDown) {
            _isKeyDown = true;
            _longPressTriggered = false;

            // Start long press timer only if onLongPress is defined
            if (widget.onLongPress != null) {
              _longPressTimer?.cancel();
              _longPressTimer = Timer(widget.longPressDuration, () {
                if (_isKeyDown && mounted) {
                  _longPressTriggered = true;
                  _handleLongPress();
                }
              });
            }
          }
          return KeyEventResult.handled;
        }

        if (event is KeyUpEvent && isSelectKey) {
          _longPressTimer?.cancel();

          // If long press wasn't triggered, it's a normal press
          if (_isKeyDown && !_longPressTriggered) {
            _handlePress();
          }

          _isKeyDown = false;
          _longPressTriggered = false;
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: _onHover,
        child: GestureDetector(
          onTap: _handlePress,
          onLongPress: widget.onLongPress,
          child: TweenAnimationBuilder<double>(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            tween: Tween<double>(
              begin: 1.0,
              end: _isFocused ? widget.scale : 1.0,
            ),
            builder: (context, double scale, child) {
              final radius = widget.borderRadius ?? BorderRadius.circular(12);
              // No shadow: a blurred shadow costs a full pass on every frame,
              // and the TV redraws everything for each frame of the preview.
              return Transform.scale(
                scale: scale,
                child: _isFocused && !widget.paintsOwnFocus
                    ? DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: widget.focusColor,
                            width: widget.borderWidth,
                          ),
                        ),
                        child: child,
                      )
                    : child,
              );
            },
            child: _TVFocusScope(focused: _isFocused, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _TVFocusScope extends InheritedWidget {
  const _TVFocusScope({required this.focused, required super.child});

  final bool focused;

  @override
  bool updateShouldNotify(_TVFocusScope oldWidget) =>
      focused != oldWidget.focused;
}
