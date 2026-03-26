import 'package:flutter/material.dart';

/// XtremFlow Apple TV Premium Color System
/// 
/// Designed for modern tvOS aesthetic:
/// - OLED-optimized blacks
/// - Sophisticated, understated accent colors
/// - Premium glass effects
/// - Apple-compliant semantic colors
class AppColors {
  AppColors._();

  // ============ BACKGROUNDS (OLED Optimized) ============
  /// Pure black, optimal for OLED screens
  static const Color background = Color(0xFF000000);

  /// Deep black with minimal elevation
  static const Color backgroundAlt = Color(0xFF0A0A0A);

  // ============ SURFACE LAYERS (Material Design 3) ============
  /// Level 1 - Primary card surfaces, containers
  static const Color surface = Color(0xFF1A1A1A);

  /// Level 2 - Elevated surfaces, hovered cards
  static const Color surfaceVariant = Color(0xFF2A2A2A);

  /// Level 3 - Disabled states, secondary containers
  static const Color surfaceTertiary = Color(0xFF3A3A3A);

  /// Level 4 - Dividers and minimal visible elements
  static const Color surfaceQuad = Color(0xFF4A4A4A);

  /// Level 5 - Premium elevated containers
  static const Color surfaceFive = Color(0xFF5A5A5A);

  // ============ PRIMARY ACCENT (Sophisticated Teal) ============
  /// Main interactive color for focus states and CTAs
  /// Refined from #00D4FF to sophisticated #00A0D2 (80% saturation)
  static const Color primary = Color(0xFF00A0D2);

  /// Darker teal for hover/pressed states
  static const Color primaryDark = Color(0xFF0092BC);

  /// Lighter teal for disabled variants
  static const Color primaryLight = Color(0xFF1BC4E5);

  // ============ SECONDARY ACCENT (Apple Red) ============
  /// Error, warning, live indicator colors
  /// Uses Apple's official red (#FF3B30)
  static const Color secondary = Color(0xFFFF3B30);

  /// Darker red for hover states
  static const Color secondaryDark = Color(0xFFE62817);

  /// Lighter red for disabled states
  static const Color secondaryLight = Color(0xFFFF6B6B);

  // ============ TERTIARY ACCENT (Apple Green) ============
  /// Success and positive state indicator
  static const Color tertiary = Color(0xFF34C759);

  // ============ PRIMARY TEXT (Hierarchy) ============
  /// Primary text - pure white for maximum readability
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text - 60% opacity white
  static const Color textSecondary = Color(0xFF999999);

  /// Tertiary text - 40% opacity white
  static const Color textTertiary = Color(0xFF666666);

  /// Quaternary text - 25% opacity white
  static const Color textQuaternary = Color(0xFF404040);

  // ============ STATE COLORS (Semantic) ============
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF32ADE6);
  static const Color disabled = Color(0xFF888888);

  // ============ FOCUS STATES (Remote Control) ============
  /// Focus border color - white for maximum contrast
  static const Color focusColor = Color(0xFFFFFFFF);

  /// Focus border (use with 2px stroke width)
  static const Color focusBorder = Color(0xFFFFFFFF);

  // ============ GLASS EFFECTS (Premium Refinement) ============
  /// Glass background - 6% white opacity (refined from 8%)
  /// Creates premium glassmorphic effect without being too visible
  static final Color glassBackground =
      const Color(0xFFFFFFFF).withOpacity(0.06);

  /// Glass border - 12% white opacity
  static final Color glassBorder =
      const Color(0xFFFFFFFF).withOpacity(0.12);

  /// Premium glass variant - 10% white opacity
  static final Color glassPremium =
      const Color(0xFFFFFFFF).withOpacity(0.10);

  /// Dark glass for overlays and scrim effects
  static final Color glassBackgroundDark =
      const Color(0xFF000000).withOpacity(0.50);

  // ============ GRADIENTS (Premium) ============
  /// Primary gradient for CTAs and highlights
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00A0D2), Color(0xFF00D4AA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background subtle gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF000000), Color(0xFF0A0A0A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Gray gradient background with glossy effect
  static const LinearGradient grayGlossyGradient = LinearGradient(
    colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ RATING & BADGE COLORS ============
  /// Premium gold for ratings and premium badges
  static const Color ratingGold = Color(0xFFFFD700);

  /// Premium indicator color
  static const Color ratingPremium = Color(0xFFFFD700);

  // ============ OVERLAY & SCRIM ============
  /// Semi-opaque overlay for modals (50%)
  static const Color overlay = Color(0x80000000);

  /// Dark scrim for modal backgrounds
  static final Color scrim = Colors.black.withOpacity(0.4);

  // ============ DIVIDERS & BORDERS ============
  /// Default border color (subtle white line at 10% opacity)
  static const Color border = Color(0x1AFFFFFF);

  /// Strong border for emphasis (20% opacity)
  static const Color borderStrong = Color(0x33FFFFFF);

  // ============ LIVE INDICATOR ============
  static const Color live = Color(0xFFFF3B30);

  // ============ COLOR SCHEME (Material 3 Compatible) ============
  /// Complete Material 3 color scheme for ThemeData
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
}
