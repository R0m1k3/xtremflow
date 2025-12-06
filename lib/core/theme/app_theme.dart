import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow Cinematic Minimalist Theme
/// 
/// Refined, content-first theme. Less noise, more focus.
class AppTheme {
  AppTheme._();

  // ============ SPACING ============
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;

  // ============ RADIUS (Tighter for professional look) ============
  static const double radiusSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusFull = 999.0;

  // ============ DARK THEME (Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    
    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      
      // AppBar: Minimalist, blends with background
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background, // Seamless
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      
      // Navigation: Simple, functional
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
           final isSelected = states.contains(WidgetState.selected);
           return IconThemeData(
             color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
           );
        }),
      ),
      
      // NavigationRail (Desktop)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        selectedIconTheme: const IconThemeData(color: AppColors.textPrimary),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      
      // Cards: Flat, subtle border
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      
      // Inputs: Clean, filled
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.all(spacing16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
      ),
      
      // Buttons: Sharp, reliable
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),

      // Text
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }

  // ============ LIGHT THEME (Minimalist) ============
  static ThemeData get lightTheme {
     final baseTheme = ThemeData.light(useMaterial3: true);
     final colors = AppColors.lightColorScheme;

     return baseTheme.copyWith(
       colorScheme: colors,
       scaffoldBackgroundColor: colors.background,
       appBarTheme: AppBarTheme(
         backgroundColor: colors.background,
         foregroundColor: colors.onSurface,
         elevation: 0,
         centerTitle: false,
         iconTheme: IconThemeData(color: colors.onSurface),
         titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
       ),
       cardTheme: CardThemeData(
         color: colors.surface,
         elevation: 0,
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(radiusMd),
           side: BorderSide(color: Colors.grey.shade300),
         ),
       ),
       textTheme: TextTheme(
         bodyLarge: GoogleFonts.inter(color: colors.onSurface),
         bodyMedium: GoogleFonts.inter(color: colors.onSurfaceVariant),
       ),
       // Can expand light theme details later if needed
     );
  }
}
