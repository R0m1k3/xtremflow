import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Horizontal carousel for displaying channels by category
///
/// Netflix-style horizontal scrolling list with:
/// - Category title with count
/// - Smooth horizontal scrolling
/// - Lazy loading support
/// - Fade edges for visual polish
class CategoryCarousel<T> extends StatelessWidget {
  final String title;
  final int? itemCount;
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double itemWidth;
  final double itemHeight;
  final double spacing;
  final EdgeInsets? padding;
  final VoidCallback? onSeeAllTap;

  const CategoryCarousel({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.itemCount,
    this.itemWidth = 180,
    this.itemHeight = 120,
    this.spacing = 12,
    this.padding,
    this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header: title, count, « Voir tout »
        Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      if (itemCount != null)
                        TextSpan(
                          text: '  $itemCount',
                          style: AppTheme.body(
                            fontSize: 16,
                            color: AppColors.textMuted,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (onSeeAllTap != null)
                TextButton.icon(
                  onPressed: onSeeAllTap,
                  iconAlignment: IconAlignment.end,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: AppTheme.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: const Text('Voir tout'),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Horizontal scrolling list with fade edges
        SizedBox(
          height: itemHeight,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  AppColors.onSurface,
                  AppColors.onSurface,
                  Colors.transparent,
                ],
                stops: [0.0, 0.02, 0.98, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: (padding?.left ?? 16)),
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => SizedBox(width: spacing),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: itemWidth,
                  height: itemHeight,
                  child: itemBuilder(context, items[index], index),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Category chip for filtering: graphite at rest, light blue when selected.
class CategoryChipButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final IconData? icon;

  const CategoryChipButton({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isSelected ? AppColors.accent : AppColors.textSecondary;
    return ChoiceChip(
      selected: isSelected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      showCheckmark: false,
      avatar: icon == null ? null : Icon(icon, size: 16, color: ink),
      label: Text(label),
      labelStyle: AppTheme.body(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accentFill
            : AppColors.surface,
      ),
      side: BorderSide(
        color: isSelected ? Colors.transparent : AppColors.hairline,
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }
}
