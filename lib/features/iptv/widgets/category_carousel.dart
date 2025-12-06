import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  if (itemCount != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$itemCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (onSeeAllTap != null)
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Voir tout',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
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
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.02, 0.98, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: (padding?.left ?? 16),
              ),
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

/// Simple category chip for filtering
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected
              ? null
              : (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
