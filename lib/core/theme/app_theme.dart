import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow Apple TV Theme
/// 
/// Focus-driven, immersive, minimal.
class AppTheme {
  AppTheme._();

  // ============ SPACING ============
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0; // Larger spacing for TV feel

  // ============ RADIUS ============
  // ============ RADIUS ============
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 32.0;

  // ============ ANIMATION ============
  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Curve curveDefault = Curves.fastOutSlowIn; // Apple-like snappy curve

  // ============ DARK THEME (TV Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    
    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      
      // Typography: San Francisco style (using Inter as proxy)
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -1.0, color: AppColors.textPrimary),
        displayMedium: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.textPrimary),
        displaySmall: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),

      // AppBar: Transparent / Glass
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      
      // Inputs: Dark, minimal, no borders unless focused
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.focusColor, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
      ),
      
      // Buttons: White pill or minimal text
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.focusColor, // White buttons
          foregroundColor: Colors.black, // Black text
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return Colors.black.withOpacity(0.1);
            if (states.contains(WidgetState.pressed)) return Colors.black.withOpacity(0.2);
            return null;
          }),
        ),
      ),
      
      // Cards: Transparent by default (content defines look)
      // cardTheme: const CardTheme(
      //   color: AppColors.surface,
      //   elevation: 0,
      //   margin: EdgeInsets.zero,
      //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radiusMd))),
      // ),

      // Dialogs: Glass/Dark
      // dialogTheme: DialogTheme(
      //   backgroundColor: const Color(0xFF1C1C1E), // Apple Dark Grey
      //   elevation: 24,
      //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      //   titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      //   contentTextStyle: GoogleFonts.inter(fontSize: 16, color: AppColors.textSecondary),
      // ),
    );
  }

  static const double radiusFull = 999.0;

  // Light theme stub
  static ThemeData get lightTheme => ThemeData.light(useMaterial3: true).copyWith(
    colorScheme: AppColors.lightColorScheme,
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
  );
}
