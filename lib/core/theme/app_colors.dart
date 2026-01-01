import 'package:flutter/material.dart';

/// XtremFlow Apple TV Style Palette
///
/// Ultra minimalist, focus-driven palette.
/// - Background: Pure Black (#000000)
/// - Focus/Active: Pure White (#FFFFFF)
/// - Inactive: Grey (#9E9E9E)
/// - Glass: Heavy blur with low opacity
class AppColors {
  AppColors._();

  // ============ BACKGROUNDS ============
  /// Pure black for that infinite depth look (OLED friendly)
  static const Color background = Color(0xFF0F1014); // Deepest Blue-Black

  /// Very deep grey for surfaces that need to be distinct but subtle (Apple Dark Grey)
  static const Color surface = Color(0xFF181920);

  /// Slightly lighter grey for secondary surfaces or hover states
  static const Color surfaceVariant = Color(0xFF1E2028);

  static const Color surfaceGlass =
      Color(0x1AFFFFFF); // 10% White for glass effect

  /// Focused element background (often white in tvOS for text, or bright accent)
  static const Color focusColor = Color(0xFFFFFFFF);
  static const Color border = Color(0xFF1F1F1F);
  static const Color focusBorder = Color(0xFFFFFFFF);

  // ============ ACCENTS ============
  static const Color primary = Color(0xFF6C63FF);
  static const Color secondary = Color(0xFF00B4D8);
  static const Color accent = Color(0xFF00B4D8);

  /// Primary Gradient (Electric Violet to Cyan)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF00B4D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0F1014), Color(0xFF131418)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Status Colors
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF5252);
  static const Color info = Color(0xFF2979FF);

  // Content Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textTertiary = Color(0xFF666666);

  static const Color ratingGold = Color(0xFFFFD700);
  static const Color premiumGold = Color(0xFFFFA000);

  // Category Colors
  static const Color live = Color(0xFFFF5252); // Red
  static const Color movies = Color(0xFF448AFF); // Blue
  static const Color series = Color(0xFF69F0AE); // Green

  // ============ GLASSMORPHISM ============
  // Apple TV uses this heavily for headers/overlays
  static final Color glassBackground = const Color(0xFF1E1E1E).withOpacity(0.6);
  static final Color glassBorder = const Color(0xFFFFFFFF).withOpacity(0.15);

  // ============ THEME SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: error,
        onPrimary: Colors
            .black, // White text on buttons -> Black text on White buttons
        onSecondary: Colors.black,
        onSurface: textPrimary,
        onError: Colors.white,
        brightness: Brightness.dark,
      );

  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Colors.black,
        secondary: Colors.grey,
        surface: Color(0xFFF2F2F7),
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onError: Colors.white,
        brightness: Brightness.light,
      );
}
