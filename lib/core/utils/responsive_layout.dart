import 'package:flutter/material.dart';

/// Responsive breakpoints and layout utilities
class ResponsiveLayout {
  ResponsiveLayout._();

  // ============ BREAKPOINTS ============
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Check if current screen is mobile size
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  /// Check if current screen is tablet size
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < desktopBreakpoint;
  }

  /// Check if current screen is desktop size
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktopBreakpoint;
  }

  /// Get current device type
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) return DeviceType.mobile;
    if (width < desktopBreakpoint) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// Get responsive value based on screen size
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    final type = getDeviceType(context);
    switch (type) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? desktop;
      case DeviceType.desktop:
        return desktop;
    }
  }

  /// Get grid columns based on screen size
  static int gridColumns(BuildContext context) {
    return value(context, mobile: 2, tablet: 3, desktop: 4);
  }

  /// Get content max width
  static double maxContentWidth(BuildContext context) {
    return value(context, mobile: double.infinity, tablet: 900, desktop: 1200);
  }
}

/// Device types for responsive layouts
enum DeviceType { mobile, tablet, desktop }

/// Widget that adapts layout based on screen size
class AdaptiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ResponsiveLayout.mobileBreakpoint) {
          return mobile;
        }
        if (constraints.maxWidth < ResponsiveLayout.desktopBreakpoint) {
          return tablet ?? desktop;
        }
        return desktop;
      },
    );
  }
}

/// Wrapper that constrains content width on large screens
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveLayout.maxContentWidth(context),
        ),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
