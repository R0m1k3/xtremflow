import 'package:flutter/material.dart';

/// XtremFlow Premium Color Palette
/// 
/// Modern dark theme with cyan/teal gradients
class AppColors {
  AppColors._();

  // ============ PRIMARY GRADIENT ============
  /// Cyan primary - main accent color
  static const Color primary = Color(0xFF00D9FF);
  
  /// Teal secondary - gradient end
  static const Color secondary = Color(0xFF00BFA5);
  
  /// Primary gradient for buttons and highlights
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ SURFACE COLORS ============
  /// Deep dark background
  static const Color background = Color(0xFF0A0E14);
  
  /// Card/elevated surface
  static const Color surface = Color(0xFF141A22);
  
  /// Lighter surface variant (hover states, inputs)
  static const Color surfaceVariant = Color(0xFF1E2630);
  
  /// Border/divider color
  static const Color border = Color(0xFF2A3441);
  
  /// Overlay color (modals, dialogs)
  static const Color overlay = Color(0xCC0A0E14);

  // ============ TEXT COLORS ============
  /// Primary text - white with high opacity
  static const Color textPrimary = Color(0xFFF5F5F5);
  
  /// Secondary text - muted
  static const Color textSecondary = Color(0xFFB0BEC5);
  
  /// Disabled/hint text
  static const Color textDisabled = Color(0xFF607D8B);

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
  /// Colors for category chips/tags
  static const List<Color> categoryColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF8B5CF6), // Purple
    Color(0xFF14B8A6), // Teal
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
  ];

  // ============ GLASSMORPHISM ============
  /// Glass effect background color
  static const Color glassBackground = Color(0x1AFFFFFF);
  
  /// Glass border color
  static const Color glassBorder = Color(0x33FFFFFF);

  // ============ DARK THEME COLOR SCHEME ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
    primary: primary,
    secondary: secondary,
    surface: surface,
    error: error,
    onPrimary: Color(0xFF000000),
    onSecondary: Color(0xFF000000),
    onSurface: textPrimary,
    onError: Color(0xFFFFFFFF),
  );
}
