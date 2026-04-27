import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Apple TV Modern Top Navigation Bar
/// 
/// Premium navigation header with:
/// - Logo/branding
/// - Search integration
/// - User menu
/// - Glassmorphism effect
class TvTopNavBar extends StatefulWidget {
  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onProfile;
  final VoidCallback? onNotifications;
  final int notificationCount;
  final Widget? leading;
  final List<Widget>? actions;

  const TvTopNavBar({
    super.key,
    required this.title,
    this.onSearch,
    this.onProfile,
    this.onNotifications,
    this.notificationCount = 0,
    this.leading,
    this.actions,
  });

  @override
  State<TvTopNavBar> createState() => _TvTopNavBarState();
}

class _TvTopNavBarState extends State<TvTopNavBar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GlassContainer(
        borderRadius: 0,
        hasBorder: false,
        showShadow: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing32,
          vertical: AppTheme.spacing16,
        ),
        margin: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Logo + Title
            Row(
              children: [
                if (widget.leading != null) widget.leading!,
                const SizedBox(width: AppTheme.spacing16),
                Text(
                  widget.title,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),

            // Right: Actions
            Row(
              children: [
                if (widget.onSearch != null) ...[
                  _buildIconButton(
                    icon: Icons.search,
                    onTap: widget.onSearch!,
                    tooltip: 'Search',
                  ),
                  const SizedBox(width: AppTheme.spacing16),
                ],

                if (widget.onNotifications != null) ...[
                  _buildIconButton(
                    icon: Icons.notifications_none,
                    onTap: widget.onNotifications!,
                    tooltip: 'Notifications',
                    badge: widget.notificationCount > 0
                        ? widget.notificationCount.toString()
                        : null,
                  ),
                  const SizedBox(width: AppTheme.spacing16),
                ],

                if (widget.onProfile != null)
                  _buildIconButton(
                    icon: Icons.account_circle,
                    onTap: widget.onProfile!,
                    tooltip: 'Profile',
                  ),

                if (widget.actions != null) ...[
                  const SizedBox(width: AppTheme.spacing16),
                  ...widget.actions!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    String? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Stack(
              children: [
                Icon(
                  icon,
                  color: AppColors.textPrimary,
                  size: 24,
                ),
                if (badge != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple TV Modern Side Navigation
/// 
/// Vertical navigation menu with:
/// - Window navigation items
/// - Collapsible menu
/// - Smooth animations
/// - Category grouping
class TvSideNav extends StatefulWidget {
  final List<TvNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  const TvSideNav({
    super.key,
    required this.items,
    this.selectedIndex = 0,
    required this.onItemSelected,
    this.expanded = true,
    this.onToggleExpanded,
  });

  @override
  State<TvSideNav> createState() => _TvSideNavState();
}

class _TvSideNavState extends State<TvSideNav> {
  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 0,
      hasBorder: false,
      showShadow: false,
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing16),
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            widget.items.length,
            (index) => _buildNavItem(
              item: widget.items[index],
              isSelected: index == widget.selectedIndex,
              onTap: () => widget.onItemSelected(index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required TvNavItem item,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing8,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing16,
            vertical: AppTheme.spacing12,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: !isSelected
                ? Border.all(color: AppColors.border)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: isSelected ? Colors.black : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: AppTheme.spacing12),
              Expanded(
                child: Text(
                  item.label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.black : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigation item model
class TvNavItem {
  final String label;
  final IconData icon;
  final String? badge;

  TvNavItem({
    required this.label,
    required this.icon,
    this.badge,
  });
}

/// Apple TV Modern Floating Action Menu
/// 
/// Context-aware floating menu with:
/// - Multiple action buttons
/// - Smooth reveal animation
/// - Accessible positioning
class TvFloatingMenu extends StatefulWidget {
  final List<TvMenuAction> actions;
  final VoidCallback? onClose;

  const TvFloatingMenu({
    super.key,
    required this.actions,
    this.onClose,
  });

  @override
  State<TvFloatingMenu> createState() => _TvFloatingMenuState();
}

class _TvFloatingMenuState extends State<TvFloatingMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTheme.durationMd,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _controller,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            widget.actions.length,
            (index) => GestureDetector(
              onTap: () {
                widget.actions[index].onTap?.call();
                widget.onClose?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing16,
                  vertical: AppTheme.spacing12,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.actions[index].icon,
                      color: widget.actions[index].color ?? AppColors.textPrimary,
                    ),
                    const SizedBox(width: AppTheme.spacing12),
                    Text(
                      widget.actions[index].label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menu action model
class TvMenuAction {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  TvMenuAction({
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
  });
}
