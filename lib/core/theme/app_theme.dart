import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow Apple TV Modern Theme
///
/// Premium, immersive design system based on tvOS 18+
/// - Focus-driven interactions
/// - Sophisticated glassmorphism
/// - Rich typography hierarchy
/// - Cinematic animations
class AppTheme {
  AppTheme._();

  // ============ SPACING (8pt system) ============
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing56 = 56.0;
  static const double spacing64 = 64.0;

  // ============ RADIUS (modern, organic curves) ============
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusXxl = 32.0;
  static const double radiusFull = 999.0;

  // ============ ELEVATION (Shadow system) ============
  static const double elevationXs = 2.0;
  static const double elevationSm = 4.0;
  static const double elevationMd = 8.0;
  static const double elevationLg = 16.0;
  static const double elevationXl = 24.0;

  // ============ ANIMATION (cinematic timing) ============
  static const Duration durationXs = Duration(milliseconds: 100);
  static const Duration durationSm = Duration(milliseconds: 150);
  static const Duration durationBase = Duration(milliseconds: 200);
  static const Duration durationMd = Duration(milliseconds: 300);
  static const Duration durationLg = Duration(milliseconds: 400);
  static const Duration durationXl = Duration(milliseconds: 600);

  // Curves
  static const Curve curveDefault = Curves.easeInOutCubic;
  static const Curve curveSnappy = Curves.fastOutSlowIn;
  static const Curve curveSmooth = Curves.easeOutCubic;
  static const Curve curveBouncy = Curves.elasticOut;

  // ============ DARK THEME (TV Main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      useMaterial3: true,
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,

      // ============ TYPOGRAPHY ============
      // Premium font stack: SF Pro Display → Outfit → Inter
      textTheme: TextTheme(
        // Display - Hero/Large titles (cinema billboards)
        displayLarge: GoogleFonts.outfit(
          fontSize: 56,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          height: 1.1,
          color: AppColors.textPrimary,
        ),

        // Display Medium - Section titles (featured content)
        displayMedium: GoogleFonts.outfit(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          height: 1.15,
          color: AppColors.textPrimary,
        ),

        // Display Small - Sub-titles
        displaySmall: GoogleFonts.outfit(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
          color: AppColors.textPrimary,
        ),

        // Headline Medium - Card titles, prominent labels
        headlineMedium: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.25,
          color: AppColors.textPrimary,
        ),

        // Headline Small - Smaller headings
        headlineSmall: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.3,
          color: AppColors.textPrimary,
        ),

        // Title Large - Labels, emphasis text
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        // Title Medium - UI elements
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        // Title Small - Secondary labels
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.4,
          color: AppColors.textSecondary,
        ),

        // Body Large - Primary body text
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          height: 1.5,
          color: AppColors.textSecondary,
        ),

        // Body Medium - Standard body text
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          height: 1.5,
          color: AppColors.textSecondary,
        ),

        // Body Small - Secondary text
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.3,
          height: 1.5,
          color: AppColors.textTertiary,
        ),

        // Label Large - Button text, prominent labels
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        // Label Medium - Secondary buttons
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        // Label Small - Badge/tags
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
      ),

      // ============ APP BAR ============
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),

      // ============ INPUTS (Search, filters, etc) ============
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 2.0),
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textTertiary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // ============ BUTTONS ============
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.1,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return AppColors.accent.withOpacity(0.2);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.accent.withOpacity(0.4);
            }
            return null;
          }),
        ),
      ),

      // Outline buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: spacing20, vertical: spacing12),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding:
              const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing8),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ============ CARDS ============
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // ============ DIALOGS & BOTTOM SHEETS ============
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: elevationXl,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: elevationLg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radiusXl),
            topRight: Radius.circular(radiusXl),
          ),
        ),
      ),

      // ============ CHIPS ============
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        disabledColor: AppColors.surfaceTertiary,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: spacing12, vertical: spacing8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // ============ SNACKBAR ============
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceTertiary,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: elevationMd,
      ),

      // ============ PROGRESS INDICATORS ============
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceVariant,
        circularTrackColor: AppColors.surfaceVariant,
      ),

      // ============ SLIDERS ============
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant,
        trackHeight: 4.0,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2900D4FF),
        valueIndicatorColor: AppColors.surfaceTertiary,
      ),

      // ============ DIVIDER ============
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
        space: spacing16,
      ),

      // ============ NAVIGATION ============
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),

      // ============ EXTENSIONS ============
      extensions: <ThemeExtension<dynamic>>[
        _AppThemeExtension.dark,
      ],
    );
  }

  // Light theme (fallback)
  static ThemeData get lightTheme {
    final baseTheme = ThemeData.light(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.lightColorScheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
    );
  }

  // ============ SPACING CONSTANTS (for convenience) ============
  static const double spacing14 = 14.0;

  // ============ SIZE CONSTANTS ============
  static const double iconSizeXs = 16.0;
  static const double iconSizeSm = 20.0;
  static const double iconSizeMd = 24.0;
  static const double iconSizeLg = 32.0;
  static const double iconSizeXl = 48.0;

  static const double buttonHeightSm = 36.0;
  static const double buttonHeightMd = 44.0;
  static const double buttonHeightLg = 52.0;

  // ============ ASPECT RATIOS ============
  static const double posterAspectRatio = 2 / 3;
  static const double landscapeAspectRatio = 16 / 9;
  static const double squareAspectRatio = 1.0;
}

/// Extension class for custom theme properties
class _AppThemeExtension extends ThemeExtension<_AppThemeExtension> {
  const _AppThemeExtension({
    this.glassShadow,
    this.focusShadow,
  });

  final List<BoxShadow>? glassShadow;
  final List<BoxShadow>? focusShadow;

  static _AppThemeExtension get dark => _AppThemeExtension(
    glassShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 20,
        spreadRadius: -5,
      ),
    ],
    focusShadow: [
      BoxShadow(
        color: AppColors.primary.withOpacity(0.4),
        blurRadius: 16,
        spreadRadius: 2,
      ),
    ],
  );

  @override
  ThemeExtension<_AppThemeExtension> copyWith({
    List<BoxShadow>? glassShadow,
    List<BoxShadow>? focusShadow,
  }) {
    return _AppThemeExtension(
      glassShadow: glassShadow ?? this.glassShadow,
      focusShadow: focusShadow ?? this.focusShadow,
    );
  }

  @override
  ThemeExtension<_AppThemeExtension> lerp(
    covariant ThemeExtension<_AppThemeExtension>? other,
    double t,
  ) {
    if (other is! _AppThemeExtension) return this;
    return this;
  }
}
