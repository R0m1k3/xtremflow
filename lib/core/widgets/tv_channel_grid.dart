import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Apple TV Modern Channel Grid
/// 
/// Responsive grid layout for channels with:
/// - Flexible column count based on screen size
/// - Smooth animations
/// - Focus-aware spacing
class TvChannelGrid extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double horizontalSpacing;
  final double verticalSpacing;
  final ScrollController? scrollController;
  final ScrollPhysics physics;

  const TvChannelGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(32, 24, 32, 32),
    this.horizontalSpacing = 20,
    this.verticalSpacing = 20,
    this.scrollController,
    this.physics = const AlwaysScrollableScrollPhysics(),
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Guard: during first Flutter Web layout pass, size may be 0 or NaN.
    // LayoutBuilder will re-trigger build once the real size is known.
    if (screenWidth <= 0 || screenWidth.isNaN || screenWidth.isInfinite) {
      return const SizedBox.shrink();
    }

    // Responsive column count
    final int columnCount;
    if (screenWidth > 1920) {
      columnCount = 6;
    } else if (screenWidth > 1600) {
      columnCount = 5;
    } else if (screenWidth > 1280) {
      columnCount = 4;
    } else if (screenWidth > 960) {
      columnCount = 3;
    } else {
      columnCount = 2;
    }

    // Calculate horizontal padding safely using resolved EdgeInsets.
    final resolvedPadding = padding.resolve(TextDirection.ltr);
    final horizontalPadding = resolvedPadding.left + resolvedPadding.right;

    // Compute item width, clamped to avoid negative/NaN values.
    final totalSpacing = horizontalSpacing * (columnCount - 1);
    final availableWidth = screenWidth - horizontalPadding - totalSpacing;
    final itemWidth = (availableWidth / columnCount).clamp(1.0, double.infinity);

    return SingleChildScrollView(
      controller: scrollController,
      physics: physics,
      padding: padding,
      child: Wrap(
        spacing: horizontalSpacing,
        runSpacing: verticalSpacing,
        children: [
          for (int i = 0; i < children.length; i++)
            SizedBox(
              width: itemWidth,
              child: children[i],
            ),
        ],
      ),
    );
  }
}

/// Apple TV Modern Horizontal Scrollable List
class TvHorizontalList extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;
  final double itemWidth;
  final double spacing;
  final ScrollController? scrollController;

  const TvHorizontalList({
    super.key,
    required this.children,
    this.title,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.itemWidth = 200,
    this.spacing = 16,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        if (title != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing32,
              vertical: AppTheme.spacing16,
            ),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),

        // Horizontal list
        SizedBox(
          height: 280,
          child: ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: 32,
              // Resolve EdgeInsetsGeometry to a concrete EdgeInsets before
              // accessing vertical — casting EdgeInsetsGeometry to double throws.
              vertical: padding.resolve(TextDirection.ltr).top,
            ),
            itemCount: children.length,
            separatorBuilder: (_, __) => SizedBox(width: spacing),
            itemBuilder: (context, index) => SizedBox(
              width: itemWidth,
              child: children[index],
            ),
          ),
        ),
      ],
    );
  }
}
