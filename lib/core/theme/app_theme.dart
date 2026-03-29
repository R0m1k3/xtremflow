import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow Apple TV Premium Theme System
///
/// Sophisticated design language based on tvOS 18+:
/// - OLED-optimized dark foundation
/// - Refined, understated accent colors
/// - Premium glassmorphic effects
/// - Focus-driven remote interaction
/// - Cinematic animations & transitions
class AppTheme {
  AppTheme._();

  // ============ SPACING (8pt base grid system) ============
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0; // TV minimum safe area
  static const double spacing56 = 56.0;
  static const double spacing64 = 64.0; // Hero section padding

  // ============ RADIUS (modern, organic curves) ============
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusXxl = 32.0;
  static const double radiusFull = 999.0;

  // ============ ELEVATION (5-level cinematic shadow system) ============
  // Simple elevation values
  static const double elevationXs = 2.0;
  static const double elevationSm = 4.0;
  static const double elevationMd = 8.0;
  static const double elevationLg = 16.0;
  static const double elevationXl = 24.0;

  // Shadow lists for advanced effects
  // Level 1: Depth 1px - minimal elevation (UI borders)
  static const List<BoxShadow> shadowXs = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  // Level 2: Depth 4px - cards, buttons
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  // Level 3: Depth 8px - hovered cards, modals
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x23000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  // Level 4: Depth 16px - elevated panels, bottom sheets
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x38000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];

  // Level 5: Depth 24px - floating menus, dropdowns
  static const List<BoxShadow> shadowXl = [
    BoxShadow(
      color: Color(0x4D000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  // ============ ANIMATION (cinematic timing for TV) ============
  // Durations designed for 10ft viewing distance
  static const Duration durationXs = Duration(milliseconds: 100);
  static const Duration durationSm = Duration(milliseconds: 150);
  static const Duration durationBase = Duration(milliseconds: 200);
  static const Duration durationMd = Duration(milliseconds: 300);
  static const Duration durationLg = Duration(milliseconds: 400);
  static const Duration durationXl = Duration(milliseconds: 600);

  /// Curves optimized for premium feel
  // Smooth deceleration for content
  static const Curve curveDefault = Curves.easeInOutCubic;
  // Quick snap for focus
  static const Curve curveSnappy = Curves.fastOutSlowIn;
  // Smooth exit for elegance
  static const Curve curveSmooth = Curves.easeOutCubic;
  // Attention-grabbing bounce
  static const Curve curveBouncy = Curves.elasticOut;

  // ============ DARK THEME (TV Main - Apple TV Modern) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,

      // ============ TYPOGRAPHY (Apple TV Optimized for 10ft Viewing) ============
      textTheme: TextTheme(
        /// Display Large - 64px (HERO TITLES)
        /// Usage: Main featured content, landing pages
        /// Increased from 56px for true presence on TV screens
        displayLarge: GoogleFonts.outfit(
          fontSize: 64,
          fontWeight: FontWeight.w800,
          letterSpacing: -2.0,
          height: 1.2,
          color: AppColors.textPrimary,
        ),

        /// Display Medium - 56px (PAGE TITLES)
        /// Usage: Section headers, featured content titles
        displayMedium: GoogleFonts.outfit(
          fontSize: 56,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
          height: 1.15,
          color: AppColors.textPrimary,
        ),

        /// Display Small - 44px (SUBSECTION TITLES)
        displaySmall: GoogleFonts.outfit(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          height: 1.2,
          color: AppColors.textPrimary,
        ),

        /// Headline Large - 32px (strong emphasis)
        headlineLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.25,
          color: AppColors.textPrimary,
        ),

        /// Headline Medium - 28px (CARD TITLES)
        /// Usage: Featured content cards, important sections
        headlineMedium: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.3,
          color: AppColors.textPrimary,
        ),

        /// Headline Small - 22px (strong labels)
        headlineSmall: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        /// Title Large - 18px (prominent UI text)
        /// Usage: Navigation, strong emphasis
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        /// Title Medium - 16px (BUTTON LABELS)
        /// Usage: Button text, input labels
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.5,
          color: AppColors.textPrimary,
        ),

        /// Title Small - 14px (SECONDARY LABELS)
        /// Usage: Secondary emphasis, hints
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.4,
          color: AppColors.textSecondary,
        ),

        /// Body Large - 16px (PRIMARY CONTENT)
        /// Usage: Main descriptions, content  text
        /// Line height INCREASED to 1.6 for TV comfort
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          height: 1.6,
          color: AppColors.textSecondary,
        ),

        /// Body Medium - 14px (SECONDARY CONTENT)
        /// Line height INCREASED to 1.6
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          height: 1.6,
          color: AppColors.textSecondary,
        ),

        /// Body Small - 12px (TERTIARY TEXT)
        /// Usage: Metadata, timestamps, specs
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          height: 1.5,
          color: AppColors.textTertiary,
        ),

        /// Label Large - 12px (BADGE TEXT)
        /// Usage: Badge text, tab labels
        labelLarge: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        /// Label Medium - 11px (SMALL BUTTONS)
        labelMedium: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          height: 1.4,
          color: AppColors.textPrimary,
        ),

        /// Label Small - 10px (TINY BADGES)
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
      ),

      // ============ APP BAR (Header Navigation) ============
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),

      // ============ INPUT DECORATION (Search, filters, text fields) ============
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing16,
          vertical: spacing12,
        ),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textTertiary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // ============ BUTTONS (Primary CTA) ============
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.disabled.withOpacity(0.4),
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing24,
            vertical: spacing12,
          ),
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
              return Colors.black.withOpacity(0.1);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.black.withOpacity(0.2);
            }
            return null;
          }),
        ),
      ),

      // ============ OUTLINED BUTTONS ============
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing20,
            vertical: spacing12,
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ============ TEXT BUTTONS (Secondary Actions) ============
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing16,
            vertical: spacing8,
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ============ CARDS (Content containers) ============
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),

      // ============ DIALOGS (Modal content) ============
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),

      // ============ BOTTOM SHEET ============
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: AppColors.primary.withOpacity(0.05),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radiusXl),
            topRight: Radius.circular(radiusXl),
          ),
        ),
      ),

      // ============ CHIPS (Tag/filter components) ============
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
        padding: const EdgeInsets.symmetric(
          horizontal: spacing12,
          vertical: spacing8,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
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
        elevation: 0,
      ),

      // ============ PROGRESS INDICATORS ============
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceVariant,
        circularTrackColor: AppColors.surfaceVariant,
        refreshBackgroundColor: AppColors.surface,
      ),

      // ============ SLIDERS ============
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant,
        trackHeight: 4.0,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2900A0D2),
        valueIndicatorColor: AppColors.surfaceTertiary,
      ),

      // ============ DIVIDER ============
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: spacing16,
      ),

      // ============ NAVIGATION RAIL (Side menu) ============
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedIconTheme: IconThemeData(
          color: AppColors.primary,
          size: 28,
        ),
        unselectedIconTheme: IconThemeData(
          color: AppColors.textSecondary,
          size: 24,
        ),
      ),

      // ============ EXTENSIONS (Custom theme properties) ============
      extensions: <ThemeExtension<dynamic>>[
        _AppThemeExtension.dark,
      ],
    );
  }

  // ============ LIGHT THEME (Fallback) ============
  static ThemeData get lightTheme {
    final baseTheme = ThemeData.light(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
    );
  }

  // ============ SIZE CONSTANTS (Icon & Button sizes) ============
  static const double iconSizeXs = 16.0;
  static const double iconSizeSm = 20.0;
  static const double iconSizeMd = 24.0;
  static const double iconSizeLg = 32.0;
  static const double iconSizeXl = 48.0;

  static const double buttonHeightSm = 36.0;
  static const double buttonHeightMd = 44.0;
  static const double buttonHeightLg = 56.0; // TV-comfortable tap target

  // ============ ASPECT RATIOS ============
  static const double posterAspectRatio = 2 / 3;
  static const double landscapeAspectRatio = 16 / 9;
  static const double squareAspectRatio = 1.0;
}

/// Custom theme extension for advanced properties
class _AppThemeExtension extends ThemeExtension<_AppThemeExtension> {
  const _AppThemeExtension({
    this.glassShadow,
    this.focusShadow,
    this.elevatedShadow,
  });

  /// Premium glass shadow effect
  final List<BoxShadow>? glassShadow;

  /// Focus state glow for remote control
  final List<BoxShadow>? focusShadow;

  /// Elevated surface shadow
  final List<BoxShadow>? elevatedShadow;

  static _AppThemeExtension get dark => _AppThemeExtension(
        glassShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            spreadRadius: -4,
          ),
        ],
        focusShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
        elevatedShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      );

  @override
  ThemeExtension<_AppThemeExtension> copyWith({
    List<BoxShadow>? glassShadow,
    List<BoxShadow>? focusShadow,
    List<BoxShadow>? elevatedShadow,
  }) {
    return _AppThemeExtension(
      glassShadow: glassShadow ?? this.glassShadow,
      focusShadow: focusShadow ?? this.focusShadow,
      elevatedShadow: elevatedShadow ?? this.elevatedShadow,
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
