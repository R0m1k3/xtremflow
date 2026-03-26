import 'package:flutter/material.dart';

/// XtremFlow Apple TV Modern Palette (tvOS 18+ inspired)
///
/// Premium, sophisticated color system designed for immersive TV viewing.
/// - Dark foundation with subtle greys
/// - Vibrant accent colors for focus states
/// - Rich glassmorphism effects
/// - Category-specific semantic colors
class AppColors {
  AppColors._();

  // ============ BACKGROUNDS ============
  /// Pure black background - OLED optimized
  static const Color background = Color(0xFF000000);

  /// Primary dark surface for cards/containers
  static const Color surface = Color(0xFF1C1C1E);

  /// Secondary surface - slightly lighter for hierarchy
  static const Color surfaceVariant = Color(0xFF2A2A2E);

  /// Tertiary surface - subtle depth
  static const Color surfaceTertiary = Color(0xFF383838);

  /// Glass effect overlay
  static const Color surfaceGlass = Color(0x0DFFFFFF);

  /// Glass border subtle line
  static const Color border = Color(0xFF3A3A3C);
  static const Color borderLight = Color(0xFF5A5A5C);
  static const Color focusBorder = Color(0xFFFFFFFF);

  // ============ PRIMARY ACCENTS ============
  /// Main brand color - vibrant and attention-grabbing
  static const Color primary = Color(0xFF00D4FF); // Cyan/Sky Blue

  /// Secondary accent for variety
  static const Color secondary = Color(0xFFFF6B6B); // Soft Red

  /// Tertiary accent for highlights
  static const Color tertiary = Color(0xFF00E5BB); // Mint

  /// Main accent for focused elements
  static const Color accent = Color(0xFF00D4FF);

  /// Focus/interactive state - white
  static const Color focusColor = Color(0xFFFFFFFF);

  // ============ GRADIENTS ============
  /// Primary action gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D4FF), Color(0xFF00E5BB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background subtle gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF000000), Color(0xFF0A0A0A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Success-to-info gradient
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00E5BB), Color(0xFF00D4FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Premium gradient for hero elements
  static const LinearGradient premiumGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFFFB347)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ SEMANTIC COLORS ============
  /// Success state - green
  static const Color success = Color(0xFF34C759);

  /// Warning state - orange/amber
  static const Color warning = Color(0xFFFF9500);

  /// Error state - red
  static const Color error = Color(0xFFFF3B30);

  /// Info state - blue
  static const Color info = Color(0xFF30B0C0);

  /// Neutral/disabled state
  static const Color disabled = Color(0xFF8E8E93);

  // ============ TEXT HIERARCHY ============
  /// Primary text - white
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text - light grey (60%)
  static const Color textSecondary = Color(0xFF999999);

  /// Tertiary text - medium grey (40%)
  static const Color textTertiary = Color(0xFF666666);

  /// Quaternary text - dark grey (25%)
  static const Color textQuaternary = Color(0xFF404040);

  // ============ CATEGORY COLORS ============
  /// Live content - bright red
  static const Color live = Color(0xFFFF3B30);

  /// Movies content - electric blue
  static const Color movies = Color(0xFF00B4E8);

  /// Series content - mint green
  static const Color series = Color(0xFF00E5BB);

  /// Sports content - purple
  static const Color sports = Color(0xFFBF5AF0);

  /// News content - yellow
  static const Color news = Color(0xFFFFC300);

  /// Music content - pink
  static const Color music = Color(0xFFFF2D55);

  // ============ RATINGS ============
  /// IMDb-style gold for ratings
  static const Color ratingGold = Color(0xFFFDB913);

  /// Premium/VIP gold
  static const Color premiumGold = Color(0xFFFFD700);

  /// Trending gradient
  static const LinearGradient trendingGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ GLASS EFFECTS ============
  /// Glass background - frozen white at 20% opacity
  static final Color glassBackground = const Color(0xFFFFFFFF).withOpacity(0.08);

  /// Glass border - white line at 15% opacity
  static final Color glassBorder = const Color(0xFFFFFFFF).withOpacity(0.15);

  /// Dark glass - for overlays
  static final Color glassBackgroundDark = const Color(0xFF000000).withOpacity(0.5);

  /// Premium glass - stronger visibility
  static final Color glassPremium = const Color(0xFFFFFFFF).withOpacity(0.12);

  // ============ OVERLAY COLORS ============
  /// Overlay for modals/dialogs
  static const Color overlay = Color(0x80000000);

  /// Scrim color
  static final Color scrim = Colors.black.withOpacity(0.4);

  /// Loading shimmer color
  static const Color shimmer = Color(0xFF2A2A2E);

  // ============ THEME SCHEMES ============
  /// Dark mode color scheme (main)
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFF000000),
        secondary: secondary,
        onSecondary: Color(0xFFFFFFFF),
        tertiary: tertiary,
        onTertiary: Color(0xFF000000),
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Color(0xFFFFFFFF),
        brightness: Brightness.dark,
        scrim: overlay,
      );

  /// Light mode color scheme (fallback)
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Color(0xFF0084FF),
        secondary: Color(0xFFFF3B30),
        surface: Color(0xFFFAFAFA),
        error: error,
        brightness: Brightness.light,
      );
}
