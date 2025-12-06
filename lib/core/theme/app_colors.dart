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
  static const Color background = Color(0xFF000000);
  
  /// Very deep grey for surfaces that need to be distinct but subtle (Apple Dark Grey)
  static const Color surface = Color(0xFF2C2C2E);
  
  /// Slightly lighter grey for secondary surfaces or hover states
  static const Color surfaceVariant = Color(0xFF3A3A3C);
  
  /// Focused element background (often white in tvOS for text, or bright accent)
  static const Color focusColor = Color(0xFFFFFFFF);

  // ============ ACCENTS ============
  /// Minimal white accent. In Apple TV, color is used sparingly.
  /// We keep a subtle blue only for specific indicators if needed.
  static const Color primary = Color(0xFFFFFFFF); 
  static const Color accent = Color(0xFFE5E5E5);

  /// Primary Gradient (Subtle silver/white glow)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFCCCCCC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ TEXT ============
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E); // Medium Grey
  static const Color textTertiary = Color(0xFF616161); // Darker Grey

  // ============ FUNCTIONAL COLORS ============
  static const Color success = Color(0xFF4DB6AC); // Teal-ish
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFEF5350);
  static const Color live = Color(0xFFFF3B30); // Apple Red

  // ============ BORDERS ============
  // Borders are usually hidden until focused
  static const Color border = Color(0xFF1F1F1F); 
  static const Color focusBorder = Color(0xFFFFFFFF);

  // ============ GLASSMORPHISM ============
  // Apple TV uses this heavily for headers/overlays
  static final Color glassBackground = const Color(0xFF1E1E1E).withOpacity(0.6);
  static final Color glassBorder = const Color(0xFFFFFFFF).withOpacity(0.15);

  // ============ THEME SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
    primary: primary,
    secondary: accent,
    surface: surface,
    background: background,
    error: error,
    onPrimary: Colors.black, // White text on buttons -> Black text on White buttons
    onSecondary: Colors.black,
    onSurface: textPrimary,
    onError: Colors.white,
    brightness: Brightness.dark,
  );

  static ColorScheme get lightColorScheme => const ColorScheme.light(
    primary: Colors.black,
    secondary: Colors.grey,
    surface: Color(0xFFF2F2F7),
    background: Colors.white,
    error: error,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Colors.black,
    onError: Colors.white,
    brightness: Brightness.light,
  );
}
