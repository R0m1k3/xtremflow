import 'package:flutter/material.dart';

/// XtremFlow Cinematic Minimalist Palette
/// 
/// A deep, dark, and neutral palette designed for content-first experiences.
/// Focuses on #0A0A0A backgrounds and subtle surfaces.
class AppColors {
  AppColors._();

  // ============ BACKGROUNDS ============
  /// Pitch black for OLED/Main backgrounds
  static const Color background = Color(0xFF0A0A0A);
  
  /// Dark grey for cards/sheets
  static const Color surface = Color(0xFF141414);
  
  /// Slightly lighter for hover states or active items
  static const Color surfaceLight = Color(0xFF1F1F1F);
  
  /// For inputs or secondary surfaces
  static const Color surfaceVariant = Color(0xFF2A2A2A);

  // ============ ACCENTS (MINIMALIST) ============
  /// Primary Brand Color (Electric Blue/Violet for modern feel)
  /// Replacing the old Gradient Cyan with a solid, punchy color.
  static const Color primary = Color(0xFF3F51B5); // Indigo
  
  /// Secondary accent
  static const Color accent = Color(0xFF7986CB);

  /// Primary Gradient (Subtle, for buttons only)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ TEXT ============
  /// Pure white for high contrast headers
  static const Color textPrimary = Color(0xFFFFFFFF);
  
  /// Light grey for body text
  static const Color textSecondary = Color(0xFFB3B3B3);
  
  /// Darker grey for hints/disabled
  static const Color textTertiary = Color(0xFF808080);
  
  // ============ FUNCTIONAL COLORS ============
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFCF6679);
  static const Color info = Color(0xFF2196F3);
  static const Color live = Color(0xFFFF0000); // Standard Red for LIVE

  // ============ BORDERS ============
  static const Color border = Color(0xFF333333);

  // ============ GLASSMORPHISM ============
  static final Color glassBackground = const Color(0xFF1E1E1E).withOpacity(0.7);
  static final Color glassBorder = const Color(0xFFFFFFFF).withOpacity(0.1);

  // ============ CATEGORY COLORS (MUTED) ============
  static const List<Color> categoryColors = [
    Color(0xFF5C6BC0), // Indigo
    Color(0xFFAB47BC), // Purple
    Color(0xFFEF5350), // Red
    Color(0xFF26A69A), // Teal
    Color(0xFFFFA726), // Orange
    Color(0xFF78909C), // Blue Grey
  ];

  // ============ THEME SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
    primary: primary,
    secondary: accent,
    surface: surface,
    background: background,
    error: error,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: textPrimary,
    onError: Colors.white,
    brightness: Brightness.dark,
  );

  // Minimalist Light Scheme (if ever toggled)
  static ColorScheme get lightColorScheme => const ColorScheme.light(
    primary: primary,
    secondary: accent,
    surface: Color(0xFFF5F5F5),
    background: Colors.white,
    error: error,
    onPrimary: Colors.white,
    onSecondary: Colors.black,
    onSurface: Color(0xFF121212),
    onError: Colors.white,
    brightness: Brightness.light,
  );
}
