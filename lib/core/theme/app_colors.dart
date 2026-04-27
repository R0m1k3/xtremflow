import 'package:flutter/material.dart';

/// Cyber-Cinematic Glass Design System — Material 3 Token Palette
///
/// Extracted from the Stitch design system for XtremFlow.
/// Optimized for OLED displays and low-light environments.
/// Primary accent: Neon blue (#4b8eff / #adc6ff)
class AppColors {
  AppColors._();

  // ============ COMPATIBILITY ALIASES (transition) ============
  static Color get focusColor => primaryContainer;
  static Color get border => outlineVariant;

  // ============ SURFACE / ON SURFACE ============
  static const Color onSurface = Color(0xFFe3e2e7);
  static const Color onSurfaceVariant = Color(0xFFc1c6d7);

  // ============ BASE LEVEL 0 ============
  static const Color baseLevel0 = Color(0xFF0F1014);

  // ============ BACKGROUNDS ============
  static const Color background = Color(0xFF121317);
  static const Color onBackground = Color(0xFFe3e2e7);

  static const Color surface = Color(0xFF121317);
  static const Color surfaceDim = Color(0xFF121317);
  static const Color surfaceBright = Color(0xFF38393d);

  // Surface Containers (Material 3 hierarchy)
  static const Color surfaceContainerLowest = Color(0xFF0d0e12);
  static const Color surfaceContainerLow = Color(0xFF1a1b20);
  static const Color surfaceContainer = Color(0xFF1f1f24);
  static const Color surfaceContainerHigh = Color(0xFF292a2e);
  static const Color surfaceContainerHighest = Color(0xFF343439);
  static const Color surfaceVariant = Color(0xFF343439);

  // ============ PRIMARY (Neon Blue) ============
  static const Color primary = Color(0xFFadc6ff);
  static const Color onPrimary = Color(0xFF002e69);
  static const Color primaryContainer = Color(0xFF4b8eff);
  static const Color onPrimaryContainer = Color(0xFF00285c);
  static const Color inversePrimary = Color(0xFF005bc1);
  static const Color primaryFixed = Color(0xFFd8e2ff);
  static const Color primaryFixedDim = Color(0xFFadc6ff);
  static const Color onPrimaryFixed = Color(0xFF001a41);
  static const Color onPrimaryFixedVariant = Color(0xFF004493);

  // ============ SECONDARY ============
  static const Color secondary = Color(0xFFc6c5cf);
  static const Color onSecondary = Color(0xFF2f3037);
  static const Color secondaryContainer = Color(0xFF4a4b53);
  static const Color onSecondaryContainer = Color(0xFFbcbbc4);
  static const Color secondaryFixed = Color(0xFFe3e1eb);
  static const Color secondaryFixedDim = Color(0xFFc6c5cf);
  static const Color onSecondaryFixed = Color(0xFF1a1b22);
  static const Color onSecondaryFixedVariant = Color(0xFF46464e);

  // ============ TERTIARY ============
  static const Color tertiary = Color(0xFFc6c6c7);
  static const Color onTertiary = Color(0xFF2f3131);
  static const Color tertiaryContainer = Color(0xFF909191);
  static const Color onTertiaryContainer = Color(0xFF282a2a);
  static const Color tertiaryFixed = Color(0xFFe2e2e2);
  static const Color tertiaryFixedDim = Color(0xFFc6c6c7);
  static const Color onTertiaryFixed = Color(0xFF1a1c1c);
  static const Color onTertiaryFixedVariant = Color(0xFF454747);

  // ============ ERROR ============
  static const Color error = Color(0xFFffb4ab);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000a);
  static const Color onErrorContainer = Color(0xFFffdad6);

  // ============ OUTLINE ============
  static const Color outline = Color(0xFF8b90a0);
  static const Color outlineVariant = Color(0xFF414755);

  // ============ INVERSE SURFACE ============
  static const Color inverseSurface = Color(0xFFe3e2e7);
  static const Color inverseOnSurface = Color(0xFF2f3035);

  // ============ SURFACE TINT ============
  static const Color surfaceTint = Color(0xFFadc6ff);

  // ============ TEXT / CONTENT COLORS ============
  static const Color textPrimary = Color(0xFFe3e2e7);
  static const Color textSecondary = Color(0xFFc1c6d7);
  static const Color textTertiary = Color(0xFF8b90a0);

  // ============ STATUS COLORS ============
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFAB00);
  static const Color info = Color(0xFF2979FF);

  // ============ CATEGORY COLORS (kept for semantic meaning) ============
  static const Color live = Color(0xFFFF5252);
  static const Color movies = Color(0xFF448AFF);
  static const Color series = Color(0xFF69F0AE);

  // ============ RATING / PREMIUM ============
  static const Color ratingGold = Color(0xFFFFD700);
  static const Color premiumGold = Color(0xFFFFA000);

  // ============ GLASSMORPHISM LEVELS ============
  static const Color glassLevel1Bg = Color(0x66121317); // 40% opacity
  static const Color glassLevel1Border = Color(0x1AFFFFFF); // 10% white

  static const Color glassLevel2Bg = Color(0x99121317); // 60% opacity
  static const Color glassLevel2Border = Color(0x1AFFFFFF); // 10% white
  static const Color glassLevel2InnerGlow = Color(0x33adc6ff); // 20% primary top-left

  // ============ GRADIENTS ============
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF007AFF), Color(0xFF00C6FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0F1014), Color(0xFF121317)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ============ GLOW / SHADOWS ============
  static Color glowPrimary(double opacity) =>
      const Color(0xFF007AFF).withOpacity(opacity);
  static Color glowPrimaryDim(double opacity) =>
      const Color(0xFFadc6ff).withOpacity(opacity);

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

  // Light scheme is minimal — Stitch is dark-only
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Color(0xFF005bc1),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFd8e2ff),
        onPrimaryContainer: Color(0xFF001a41),
        secondary: Color(0xFF5e5c68),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFe3e1eb),
        onSecondaryContainer: Color(0xFF1a1b22),
        error: Color(0xFFba1a1a),
        onError: Colors.white,
        errorContainer: Color(0xFFFFdad6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFF9F9FF),
        onSurface: Color(0xFF1a1b22),
        outline: Color(0xFF757680),
        outlineVariant: Color(0xFFc5c6d0),
        brightness: Brightness.light,
      );
}
