import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Thème mobile XtremFlow — déclinaison tactile de « Warm Cinema ».
///
/// Mêmes tokens que [AppTheme] (charbon chaud / crème / braise), échelles
/// typographiques réduites et cibles tactiles élargies.
class MobileTheme {
  MobileTheme._();

  // ============ ESPACEMENT ============
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // ============ RAYONS (alignés sur AppTheme) ============
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 20.0;

  // ============ DARK THEME (Mobile Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,

      // Typography: Scaled down for mobile
      textTheme: TextTheme(
        displayLarge: GoogleFonts.fraunces(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
          height: 1.1,
          color: AppColors.onSurface,
        ),
        displayMedium: GoogleFonts.fraunces(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          height: 1.2,
          color: AppColors.onSurface,
        ),
        displaySmall: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: AppColors.onSurface,
        ),
        headlineMedium: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: AppColors.onSurface,
        ),
        titleLarge: GoogleFonts.fraunces(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
        titleMedium: GoogleFonts.karla(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
        bodyLarge: GoogleFonts.karla(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
        bodyMedium: GoogleFonts.karla(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
        labelLarge: GoogleFonts.karla(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.05,
          height: 1.2,
          color: AppColors.onSurface,
        ),
        labelMedium: GoogleFonts.karla(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
          height: 1.2,
          color: AppColors.onSurface,
        ),
        labelSmall: GoogleFonts.karla(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
          height: 1.2,
          color: AppColors.onSurfaceVariant,
        ),
      ),

      // AppBar: Transparent / Glass
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        // Opaque : une barre translucide impose une couche de composition
        // supplementaire sur toute la largeur, a chaque frame.
        backgroundColor: AppColors.surfaceContainerLowest,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.outline,
        selectedLabelStyle: GoogleFonts.karla(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.karla(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: AppColors.primaryContainer,
            width: 2,
          ),
        ),
        hintStyle: GoogleFonts.karla(
          color: AppColors.outline,
          fontSize: 14,
        ),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Braise profonde : seule variante qui tient le contraste AA
          // (4,5:1) avec du texte blanc.
          backgroundColor: AppColors.primaryFill,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.karla(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.glassLevel1Border, width: 1),
        ),
      ),
    );
  }
}
