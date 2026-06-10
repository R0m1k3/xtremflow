import 'package:flutter/material.dart';

/// Projector Noir Design System — Material 3 Token Palette
///
/// Warm tungsten light on deep film-black, like a projector beam cutting
/// through a dark screening room. Verdigris teal as the counterpoint accent.
/// Optimized for OLED displays and low-light environments.
/// Primary accent: Tungsten amber (#F39A1F / #FFB35C)
class AppColors {
  AppColors._();

  // ============ COMPATIBILITY ALIASES (transition) ============
  static Color get focusColor => primaryContainer;
  static Color get border => outlineVariant;

  // ============ SURFACE / ON SURFACE ============
  static const Color onSurface = Color(0xFFECE6DA);
  static const Color onSurfaceVariant = Color(0xFFCDC4B4);

  // ============ BASE LEVEL 0 ============
  static const Color baseLevel0 = Color(0xFF0B0A08);

  // ============ BACKGROUNDS ============
  static const Color background = Color(0xFF14110C);
  static const Color onBackground = Color(0xFFECE6DA);

  static const Color surface = Color(0xFF14110C);
  static const Color surfaceDim = Color(0xFF14110C);
  static const Color surfaceBright = Color(0xFF3E382C);

  // Surface Containers (Material 3 hierarchy)
  static const Color surfaceContainerLowest = Color(0xFF0E0C09);
  static const Color surfaceContainerLow = Color(0xFF1B1812);
  static const Color surfaceContainer = Color(0xFF211D16);
  static const Color surfaceContainerHigh = Color(0xFF2B261E);
  static const Color surfaceContainerHighest = Color(0xFF363027);
  static const Color surfaceVariant = Color(0xFF363027);

  // ============ PRIMARY (Tungsten Amber) ============
  static const Color primary = Color(0xFFFFB35C);
  static const Color onPrimary = Color(0xFF452800);
  static const Color primaryContainer = Color(0xFFF39A1F);
  static const Color onPrimaryContainer = Color(0xFF2E1B00);
  static const Color inversePrimary = Color(0xFF8F5B00);
  static const Color primaryFixed = Color(0xFFFFDDB3);
  static const Color primaryFixedDim = Color(0xFFFFB35C);
  static const Color onPrimaryFixed = Color(0xFF2A1700);
  static const Color onPrimaryFixedVariant = Color(0xFF6B4300);

  // ============ SECONDARY (Warm Taupe) ============
  static const Color secondary = Color(0xFFD3C6B2);
  static const Color onSecondary = Color(0xFF382F21);
  static const Color secondaryContainer = Color(0xFF504535);
  static const Color onSecondaryContainer = Color(0xFFD8CCB9);
  static const Color secondaryFixed = Color(0xFFF0E4D0);
  static const Color secondaryFixedDim = Color(0xFFD3C6B2);
  static const Color onSecondaryFixed = Color(0xFF231B0E);
  static const Color onSecondaryFixedVariant = Color(0xFF4D4232);

  // ============ TERTIARY (Verdigris Teal) ============
  static const Color tertiary = Color(0xFFA4CCBE);
  static const Color onTertiary = Color(0xFF0F352B);
  static const Color tertiaryContainer = Color(0xFF2F5A4C);
  static const Color onTertiaryContainer = Color(0xFFC0E8D9);
  static const Color tertiaryFixed = Color(0xFFC0E8D9);
  static const Color tertiaryFixedDim = Color(0xFFA4CCBE);
  static const Color onTertiaryFixed = Color(0xFF04201A);
  static const Color onTertiaryFixedVariant = Color(0xFF274B40);

  // ============ ERROR ============
  static const Color error = Color(0xFFffb4ab);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000a);
  static const Color onErrorContainer = Color(0xFFffdad6);

  // ============ OUTLINE ============
  static const Color outline = Color(0xFF998F7C);
  static const Color outlineVariant = Color(0xFF4A4334);

  // ============ INVERSE SURFACE ============
  static const Color inverseSurface = Color(0xFFECE6DA);
  static const Color inverseOnSurface = Color(0xFF332F26);

  // ============ SURFACE TINT ============
  static const Color surfaceTint = Color(0xFFFFB35C);

  // ============ TEXT / CONTENT COLORS ============
  static const Color textPrimary = Color(0xFFECE6DA);
  static const Color textSecondary = Color(0xFFCDC4B4);
  static const Color textTertiary = Color(0xFF998F7C);

  // ============ STATUS COLORS ============
  static const Color success = Color(0xFF6BD89B);
  static const Color warning = Color(0xFFFFAB00);
  static const Color info = Color(0xFF64B6AC);

  // ============ CATEGORY COLORS (kept for semantic meaning) ============
  static const Color live = Color(0xFFFF6E5E);
  static const Color movies = Color(0xFFE8B64C);
  static const Color series = Color(0xFF5FC9AE);

  // ============ RATING / PREMIUM ============
  static const Color ratingGold = Color(0xFFFFD166);
  static const Color premiumGold = Color(0xFFFFA000);

  // ============ GLASSMORPHISM LEVELS ============
  static const Color glassLevel1Bg = Color(0x6614110C); // 40% opacity
  static const Color glassLevel1Border = Color(0x1AFFE9C9); // 10% warm white

  static const Color glassLevel2Bg = Color(0x9914110C); // 60% opacity
  static const Color glassLevel2Border = Color(0x1AFFE9C9); // 10% warm white
  static const Color glassLevel2InnerGlow = Color(0x33FFB35C); // 20% primary top-left

  // ============ GRADIENTS ============
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFE8941A), Color(0xFFFFC36A)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0B0A08), Color(0xFF14110C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ============ GLOW / SHADOWS ============
  static Color glowPrimary(double opacity) =>
      const Color(0xFFF39A1F).withOpacity(opacity);
  static Color glowPrimaryDim(double opacity) =>
      const Color(0xFFFFB35C).withOpacity(opacity);

  // ============ COLOR SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        surfaceTint: surfaceTint,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        inversePrimary: inversePrimary,
        brightness: Brightness.dark,
      );

  // Light scheme is minimal — Projector Noir is dark-first
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Color(0xFF8F5B00),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFDDB3),
        onPrimaryContainer: Color(0xFF2A1700),
        secondary: Color(0xFF6F6353),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFF0E4D0),
        onSecondaryContainer: Color(0xFF231B0E),
        error: Color(0xFFba1a1a),
        onError: Colors.white,
        errorContainer: Color(0xFFFFdad6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFFFF8F0),
        onSurface: Color(0xFF1E1B15),
        outline: Color(0xFF7F766A),
        outlineVariant: Color(0xFFD0C5B4),
        brightness: Brightness.light,
      );
}
