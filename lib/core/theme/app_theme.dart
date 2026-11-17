import 'package:flutter/material.dart';

import 'app_colors.dart';

/// XtremFlow — « Salle obscure » theme.
///
/// Typography: **Figtree** only — open, round shapes with a large x-height,
/// legible from the sofa and on a phone at arm's length. Weights 400 and 500
/// (600 only for the phone's large title). Hierarchy comes from size and
/// colour, not weight. No negative tracking, no uppercase tracked labels.
/// The static files (400/500/600) are bundled in `assets/fonts/` and declared
/// in `pubspec.yaml`: no request to Google, ever.
class AppTheme {
  AppTheme._();

  // ============ SPACING (4dp grid) ============
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;
  static const double spacingBase = 8.0;
  static const double spacing2xl = 48.0;
  static const double spacing3xl = 80.0;

  // Semantic aliases
  static const double spacingXs = spacing4;
  static const double spacingSm = spacing8;
  static const double spacingMd = spacing16;
  static const double spacingLg = spacing24;
  static const double spacingXl = spacing32;

  // ============ RADIUS (nested) ============
  // logo tile 6 · row 10 · field and group card 12 · card 14 · panel 16
  static const double radiusNone = 0.0;
  static const double radiusXs = 4.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusField = 12.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 16.0;
  static const double radiusFull = 9999.0;

  // ============ MOTION ============
  /// One curve for the whole app.
  static const Curve curveFocus = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Duration durationFocus = Duration(milliseconds: 150);

  static const Duration durationXs = Duration(milliseconds: 120);
  static const Duration durationFast = durationFocus;
  static const Duration durationSm = durationFocus;
  static const Duration durationNormal = Duration(milliseconds: 220);
  static const Duration durationMd = Duration(milliseconds: 220);
  static const Duration durationLg = Duration(milliseconds: 300);
  static const Duration durationXl = Duration(milliseconds: 400);

  static const Curve curveDefault = curveFocus;
  static const Curve curveSmooth = curveFocus;
  static const Curve curveCinema = curveFocus;

  /// Tabular figures for times, channel numbers and counts.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ============ FONT ============
  /// The only family of the interface (bundled, see `pubspec.yaml`).
  static const String fontFamily = 'Figtree';

  /// Drop-in replacement for the former `GoogleFonts.xxx(...)` calls: same
  /// named parameters, always Figtree. The charter's rules are applied here:
  /// weights above 600 come back to 600 (only 400/500/600 are bundled, a
  /// heavier weight would be synthesised) and negative tracking comes back
  /// to 0.
  static TextStyle font({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    final base = textStyle ?? const TextStyle();
    final weight = fontWeight ?? base.fontWeight;
    final spacing = letterSpacing ?? base.letterSpacing;
    return base.copyWith(
      fontFamily: fontFamily,
      color: foreground == null ? color : null,
      backgroundColor: background == null ? backgroundColor : null,
      fontSize: fontSize,
      fontWeight: weight == null || weight.value <= 600
          ? weight
          : FontWeight.w600,
      fontStyle: fontStyle,
      letterSpacing: spacing == null || spacing >= 0 ? spacing : 0,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  // ============ TYPE HELPERS ============
  /// Large titles. Same family as the body: one family for the interface.
  static TextStyle display({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w500,
    double? letterSpacing,
    double? height,
    Color color = AppColors.textPrimary,
    FontStyle? fontStyle,
  }) {
    return font(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height ?? 1.15,
      color: color,
    );
  }

  /// Interface and body text.
  static TextStyle body({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    Color color = AppColors.textPrimary,
    List<FontFeature>? fontFeatures,
  }) {
    return font(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontFeatures: fontFeatures,
    );
  }

  /// Small label — sentence case, muted, no wide tracking.
  static TextStyle eyebrow({
    double fontSize = 13,
    Color color = AppColors.textMuted,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return font(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.2,
      color: color,
    );
  }

  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: display(fontSize: 40, height: 1.1, color: primary),
      displayMedium: display(fontSize: 34, height: 1.1, color: primary),
      displaySmall: display(fontSize: 28, height: 1.15, color: primary),
      headlineLarge: display(fontSize: 28, height: 1.15, color: primary),
      headlineMedium: display(fontSize: 24, height: 1.2, color: primary),
      headlineSmall: display(fontSize: 20, height: 1.25, color: primary),
      titleLarge: body(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: primary,
      ),
      titleMedium: body(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: primary,
      ),
      titleSmall: body(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: primary,
      ),
      bodyLarge: body(fontSize: 16, height: 1.5, color: secondary),
      bodyMedium: body(fontSize: 14, height: 1.5, color: secondary),
      bodySmall: body(fontSize: 13, height: 1.45, color: secondary),
      labelLarge: body(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      labelMedium: body(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      labelSmall: body(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
    );
  }

  // ============ DARK THEME (main) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: fontFamily,
    );

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashColor: AppColors.onSurface06,
      highlightColor: AppColors.onSurface06,
      focusColor: AppColors.onSurface12,
      hoverColor: AppColors.onSurface06,
      textTheme: _textTheme(
        primary: AppColors.textPrimary,
        secondary: AppColors.textSecondary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.textPrimary,
        selectionColor: AppColors.onSurface24,
        selectionHandleColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: display(fontSize: 20, color: AppColors.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentFill,
        height: 64,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => body(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.rail,
        indicatorColor: AppColors.accentFill,
        minWidth: 80,
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: const IconThemeData(
          size: 22,
          color: AppColors.accent,
        ),
        unselectedIconTheme: const IconThemeData(
          size: 22,
          color: AppColors.textMuted,
        ),
        selectedLabelTextStyle: body(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        unselectedLabelTextStyle: body(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: body(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: body(fontSize: 12, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing16,
          vertical: spacing12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: AppColors.textSecondary),
        ),
        hintStyle: body(fontSize: 15, color: AppColors.textMuted),
      ),
      // Primary button: the lit surface with dark ink.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.focus,
          foregroundColor: AppColors.onFocus,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing24,
            vertical: spacing16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusField),
          ),
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.focus,
          foregroundColor: AppColors.onFocus,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusField),
          ),
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.track),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusField),
          ),
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        titleTextStyle: display(fontSize: 20, color: AppColors.textPrimary),
        contentTextStyle: body(fontSize: 15, color: AppColors.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.focus,
        contentTextStyle: body(fontSize: 15, color: AppColors.onFocus),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusField),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.textPrimary,
        inactiveTrackColor: AppColors.track,
        thumbColor: AppColors.textPrimary,
        overlayColor: AppColors.onSurface12,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.textSecondary,
        linearTrackColor: AppColors.track,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onFocus
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.focus
              : AppColors.surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
      ),
    );
  }

  /// The charter has no light mode: the light theme is the dark one.
  static ThemeData get lightTheme => darkTheme;
}
