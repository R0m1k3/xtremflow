import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow Cyber-Cinematic Glass Theme
///
/// Design system extracted from Google Stitch.
/// Fonts: Space Grotesk (headlines) + Inter (body/labels)
/// Style: Dark-only glassmorphism with neon blue accents.
class AppTheme {
  AppTheme._();

  // ============ SPACING (8px rhythmic system) ============
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingBase = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2xl = 48.0;
  static const double spacing3xl = 80.0;

  // ============ RADIUS ============
  static const double radiusNone = 0.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 9999.0;

  // ============ ANIMATION ============
  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Curve curveDefault = Curves.fastOutSlowIn;

  // ============ TYPOGRAPHY HELPERS ============
  static TextStyle _spaceGrotesk({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  static TextStyle _inter({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  // ============ DARK THEME (Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,

      // Typography
      textTheme: TextTheme(
        // Display / Headline (Space Grotesk)
        displayLarge: _spaceGrotesk(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
          height: 1.1,
        ),
        displayMedium: _spaceGrotesk(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          height: 1.2,
        ),
        displaySmall: _spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        headlineLarge: _spaceGrotesk(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          height: 1.2,
        ),
        headlineMedium: _spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        headlineSmall: _spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        titleLarge: _spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: _inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: _inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        // Body (Inter)
        bodyLarge: _inter(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: AppColors.onSurfaceVariant,
        ),
        bodyMedium: _inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
        bodySmall: _inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: AppColors.onSurfaceVariant,
        ),
        // Labels (Inter with tracking)
        labelLarge: _inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.05,
          height: 1.2,
        ),
        labelMedium: _inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
          height: 1.2,
        ),
        labelSmall: _inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
          height: 1.2,
        ),
      ),

      // AppBar: Transparent glass
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: _spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Inputs: Dark filled with blue glow on focus
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
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
          borderSide: const BorderSide(color: AppColors.primaryContainer, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        hintStyle: _inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.outline,
        ),
        labelStyle: _inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurfaceVariant,
        ),
      ),

      // Buttons: Gradient primary, ghost secondary
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.onPrimaryContainer,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withOpacity(0.1);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withOpacity(0.2);
            }
            return null;
          }),
        ),
      ),

      // Outlined buttons: ghost style
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
          ),
        ),
      ),

      // Text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: _inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Cards: Glass style
      cardTheme: CardThemeData(
        color: AppColors.glassLevel1Bg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.glassLevel1Border, width: 1),
        ),
      ),

      // Dialogs: Floating glass
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.glassLevel2Bg,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: AppColors.glassLevel2Border, width: 1),
        ),
        titleTextStyle: _spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: _inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurfaceVariant,
        ),
      ),

      // Bottom sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        contentTextStyle: _inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Chips: Pill shaped
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        deleteIconColor: AppColors.onSurface,
        disabledColor: AppColors.surfaceContainerHighest,
        selectedColor: AppColors.primaryContainer,
        secondarySelectedColor: AppColors.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: StadiumBorder(
          side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
        ),
        labelStyle: _inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
        secondaryLabelStyle: _inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.onPrimaryContainer,
        ),
      ),

      // Tabs
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.onSurface,
        unselectedLabelColor: AppColors.outline,
        indicatorColor: AppColors.primaryContainer,
        labelStyle: _inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: _inter(fontSize: 14, fontWeight: FontWeight.w500),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.outlineVariant),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.onPrimary;
          }
          return AppColors.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryContainer;
          }
          return AppColors.surfaceContainerHighest;
        }),
      ),
    );
  }

  // Light theme is minimal — Stitch is dark-only
  static ThemeData get lightTheme => ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: AppColors.lightColorScheme,
        scaffoldBackgroundColor: AppColors.lightColorScheme.surface,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      );
}
