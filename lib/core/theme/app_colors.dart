import 'package:flutter/material.dart';

/// XtremFlow Premium Color Palette
/// 
/// Modern theme with cyan/teal gradients - supports light and dark modes
class AppColors {
  AppColors._();

  // ============ PRIMARY GRADIENT ============
  /// Cyan primary - main accent color
  static const Color primary = Color(0xFF00BCD4);
  
  /// Teal secondary - gradient end
  static const Color secondary = Color(0xFF00ACC1);
  
  /// Primary gradient for buttons and highlights
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ DARK MODE SURFACE COLORS ============
  /// Deep dark background
  static const Color backgroundDark = Color(0xFF0A0E1A);
  
  /// Card/elevated surface (dark)
  static const Color surfaceDark = Color(0xFF121829);
  
  /// Lighter surface variant (dark)
  static const Color surfaceVariantDark = Color(0xFF1E2638);
  
  /// Border/divider color (dark)
  static const Color borderDark = Color(0xFF2A3441);

  // ============ LIGHT MODE SURFACE COLORS ============
  /// Light background
  static const Color backgroundLight = Color(0xFFF5F7FA);
  
  /// Card/elevated surface (light)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  
  /// Lighter surface variant (light)
  static const Color surfaceVariantLight = Color(0xFFF0F2F5);
  
  /// Border/divider color (light)
  static const Color borderLight = Color(0xFFE2E8F0);

  // ============ DARK MODE TEXT COLORS ============
  static const Color textPrimaryDark = Color(0xFFF5F5F5);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textDisabledDark = Color(0xFF64748B);

  // ============ LIGHT MODE TEXT COLORS ============
  static const Color textPrimaryLight = Color(0xFF1A1A2E);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textDisabledLight = Color(0xFF94A3B8);

  // ============ LEGACY ALIASES (for backwards compatibility) ============
  static const Color background = backgroundDark;
  static const Color surface = surfaceDark;
  static const Color surfaceVariant = surfaceVariantDark;
  static const Color border = borderDark;
  static const Color textPrimary = textPrimaryDark;
  static const Color textSecondary = textSecondaryDark;
  static const Color textDisabled = textDisabledDark;
  static const Color overlay = Color(0xCC0A0E14);

  // ============ ACCENT COLORS ============
  /// Live indicator red
  static const Color live = Color(0xFFFF6B6B);
  
  /// Success green
  static const Color success = Color(0xFF4ADE80);
  
  /// Warning amber
  static const Color warning = Color(0xFFFBBF24);
  
  /// Error red
  static const Color error = Color(0xFFEF4444);
  
  /// Info blue
  static const Color info = Color(0xFF3B82F6);

  // ============ CATEGORY COLORS ============
  static const List<Color> categoryColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF8B5CF6), // Purple
    Color(0xFF14B8A6), // Teal
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
  ];

  // ============ GLASSMORPHISM ============
  static const Color glassBackground = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassBackgroundLight = Color(0x40FFFFFF);
  static const Color glassBorderLight = Color(0x20000000);

  // ============ DARK THEME COLOR SCHEME ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
    primary: primary,
    secondary: secondary,
    surface: surfaceDark,
    error: error,
    onPrimary: Color(0xFF000000),
    onSecondary: Color(0xFF000000),
    onSurface: textPrimaryDark,
    onError: Color(0xFFFFFFFF),
  );

  // ============ LIGHT THEME COLOR SCHEME ============
  static ColorScheme get lightColorScheme => const ColorScheme.light(
    primary: primary,
    secondary: secondary,
    surface: surfaceLight,
    error: error,
    onPrimary: Color(0xFFFFFFFF),
    onSecondary: Color(0xFFFFFFFF),
    onSurface: textPrimaryLight,
    onError: Color(0xFFFFFFFF),
  );
}

