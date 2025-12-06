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
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // ============ ANIMATION ============
  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Curve curveDefault = Curves.easeOutCubic;

  // ============ DARK THEME (TV Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    
    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      
      // AppBar: Totally transparent, content floats below
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, 
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
      
      // NavigationBar: Minimal, often just icons or text
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        iconTheme: WidgetStateProperty.resolveWith((states) {
           final isSelected = states.contains(WidgetState.selected);
           // Selected: White and slightly larger/glowing
           // Unselected: Grey and smaller
           return IconThemeData(
             color: isSelected ? AppColors.focusColor : AppColors.textSecondary,
             size: isSelected ? 28 : 24,
           );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.focusColor : AppColors.textSecondary,
          );
        }),
      ),
      
      // Cards: No background by default, they pop on focus
      cardTheme: CardThemeData(
        color: Colors.transparent, // Background comes from container in widget
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      
      // Inputs: Minimal, dark pills
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull), // Pill shape
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          borderSide: const BorderSide(color: AppColors.focusColor, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
      ),
      
      // Buttons: White pill buttons usually
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.focusColor, // White buttons
          foregroundColor: Colors.black, // Black text
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusFull),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(Colors.black.withOpacity(0.1)),
        ),
      ),

      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }

  static const double radiusFull = 999.0;

  // Light theme stub (TV interfaces rarely use light mode, but good for completeness)
  static ThemeData get lightTheme => ThemeData.light(useMaterial3: true).copyWith(
    colorScheme: AppColors.lightColorScheme,
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusFull),
            borderSide: BorderSide.none)),
  );
}
