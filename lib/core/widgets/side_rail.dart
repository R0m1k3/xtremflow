import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/iptv/widgets/playlist_selector_button.dart';
import '../models/playlist_config.dart';
import '../navigation/search_requests.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'app_dialog.dart';
import 'tv_focusable.dart';
import 'xtremflow_mark.dart';

/// Side rail of the web dashboard.
///
/// Folded to [collapsedWidth] (icons only), it unfolds to [expandedWidth]
/// (icons and labels) while the mouse is over it or while the keyboard focus
/// is inside it. It is laid over the content, which keeps a fixed
/// [collapsedWidth] inset: the content never moves.
///
/// Tabs (the dashboard's `IndexedStack`): 0 Direct, 1 Films, 2 Séries,
/// 3 Enregistrements, 4 Réglages.
class SideRail extends ConsumerStatefulWidget {
  const SideRail({
    super.key,
    required this.index,
    required this.onSelect,
    required this.playlist,
    this.onFocusContent,
  });

  static const double collapsedWidth = 88;
  static const double expandedWidth = 240;

  /// Under this width the labels are hidden.
  static const double _labelsFrom = 160;

  final int index;
  final ValueChanged<int> onSelect;
  final PlaylistConfig playlist;

  /// Right arrow from the rail: give the focus back to the content.
  final VoidCallback? onFocusContent;

  @override
  ConsumerState<SideRail> createState() => _SideRailState();
}

class _SideRailState extends ConsumerState<SideRail> {
  bool _hovered = false;
  bool _hasFocus = false;

  /// The last input was a key (not the mouse). A focus left in the rail by a
  /// hover must not keep it unfolded once the mouse has gone.
  bool _keyboard = false;

  bool get _expanded => _hovered || (_hasFocus && _keyboard);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!_keyboard) {
      _keyboard = true;
      if (_hasFocus && mounted) setState(() {});
    }
    return false;
  }

  void _search() {
    if (widget.index > 2) widget.onSelect(0);
    searchRequests.value++;
  }

  Future<void> _account() async {
    final auth = ref.read(authProvider);
    final user = auth.currentUser;
    await showAppDialog<void>(
      context,
      builder: (ctx) => AppDialog(
        title: user?.username ?? 'Compte',
        width: 380,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.isAdmin) ...[
              AppDialogTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Administration',
                autofocus: true,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.go('/admin');
                },
              ),
              const SizedBox(height: 8),
            ],
            AppDialogTile(
              icon: Icons.logout_rounded,
              label: 'Se déconnecter',
              autofocus: !auth.isAdmin,
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(authProvider.notifier).logout();
                if (mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;
    return MouseRegion(
      onEnter: (_) => setState(() {
        _hovered = true;
        _keyboard = false;
      }),
      onExit: (_) => setState(() {
        _hovered = false;
        _keyboard = false;
      }),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _hasFocus = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight &&
              widget.onFocusContent != null) {
            widget.onFocusContent!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: AppTheme.durationFocus,
          curve: AppTheme.curveFocus,
          width: expanded ? SideRail.expandedWidth : SideRail.collapsedWidth,
          decoration: BoxDecoration(
            color: AppColors.rail.withValues(alpha: .92),
            border: const Border(right: BorderSide(color: AppColors.hairline)),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final labels = c.maxWidth >= SideRail._labelsFrom;
              return FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ClipRect(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 40,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 9),
                              child: c.maxWidth >= 220
                                  ? const XtremFlowWordmark(markHeight: 28)
                                  : const XtremFlowMark(height: 28),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        RailItem(
                          icon: Icons.search_rounded,
                          label: 'Rechercher',
                          showLabel: labels,
                          onPressed: _search,
                        ),
                        const SizedBox(height: 16),
                        for (final (i, icon, label) in const [
                          (0, Icons.live_tv_rounded, 'Direct'),
                          (1, Icons.movie_outlined, 'Films'),
                          (2, Icons.video_library_outlined, 'Séries'),
                          (
                            3,
                            Icons.fiber_smart_record_outlined,
                            'Enregistrements',
                          ),
                        ]) ...[
                          RailItem(
                            icon: icon,
                            label: label,
                            showLabel: labels,
                            selected: widget.index == i,
                            onPressed: () => widget.onSelect(i),
                          ),
                          const SizedBox(height: 6),
                        ],
                        const Spacer(),
                        PlaylistSelectorButton(
                          current: widget.playlist,
                          showLabel: labels,
                        ),
                        const SizedBox(height: 6),
                        RailItem(
                          icon: Icons.settings_outlined,
                          label: 'Réglages',
                          showLabel: labels,
                          selected: widget.index == 4,
                          onPressed: () => widget.onSelect(4),
                        ),
                        const SizedBox(height: 6),
                        RailItem(
                          icon: Icons.account_circle_outlined,
                          label:
                              ref.watch(authProvider).currentUser?.username ??
                              'Compte',
                          showLabel: labels,
                          onPressed: _account,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One item of the [SideRail]: 48 px high, radius 12. The current tab has the
/// accent fill; the focused (or hovered) item is the lit glass pane.
class RailItem extends StatelessWidget {
  const RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showLabel = false,
    this.selected = false,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final bool showLabel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: _MaybeTooltip(
        message: showLabel ? null : label,
        child: TVFocusable(
          onPressed: onPressed,
          paintsOwnFocus: true,
          scale: 1,
          borderRadius: BorderRadius.circular(12),
          child: Builder(
            builder: (context) {
              final lit = TVFocusable.isFocused(context);
              final ink = lit
                  ? AppColors.onFocus
                  : selected
                  ? AppColors.accent
                  : AppColors.textSecondary;
              return AnimatedContainer(
                duration: AppTheme.durationFocus,
                curve: AppTheme.curveFocus,
                height: 48,
                decoration: lit
                    ? const GlassDecoration(lit: 1, radius: 12, halo: false)
                    : BoxDecoration(
                        color: selected
                            ? AppColors.accentFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Icon(icon, size: 24, color: ink),
                    ),
                    if (showLabel)
                      Positioned(
                        left: 50,
                        right: 10,
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _Label(
                            label: label,
                            sublabel: sublabel,
                            ink: ink,
                            muted: lit
                                ? AppColors.onFocusMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.ink,
    required this.muted,
    this.sublabel,
  });

  final String label;
  final String? sublabel;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppTheme.durationFocus,
      curve: AppTheme.curveFocus,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sublabel != null)
            Text(
              sublabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(fontSize: 11.5, color: muted),
            ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) => message == null
      ? child
      : Tooltip(
          message: message,
          waitDuration: const Duration(milliseconds: 600),
          child: child,
        );
}
