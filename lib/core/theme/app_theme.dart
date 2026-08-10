import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow — Thème « Warm Cinema »
///
/// Typo : Fraunces (display, serif éditorial) + Karla (corps / UI).
/// Style : charbon chaud, crème, orange brûlé. Profondeur par l'ombre,
/// jamais par le flou — aucun `BackdropFilter` dans tout le thème.
class AppTheme {
  AppTheme._();

  // ============ ESPACEMENT (rythme 4 / 8) ============
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingBase = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2xl = 48.0;
  static const double spacing3xl = 80.0;

  // Alias numériques (utilisés dans plusieurs écrans)
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;

  // ============ RAYONS ============
  // Cinéma : angles doux mais assumés, jamais des bulles.
  static const double radiusNone = 0.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;

  // ============ ANIMATION ============
  // Rythme lent, « fondu de projection ».
  static const Duration durationXs = Duration(milliseconds: 120);
  static const Duration durationFast = Duration(milliseconds: 180);
  static const Duration durationNormal = Duration(milliseconds: 260);
  static const Duration durationSm = Duration(milliseconds: 180);
  static const Duration durationMd = Duration(milliseconds: 260);
  static const Duration durationLg = Duration(milliseconds: 380);
  static const Duration durationXl = Duration(milliseconds: 520);

  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveSmooth = Curves.easeOutCubic;

  /// Courbe « entrée cinéma » : démarre vite, s'installe lentement.
  static const Curve curveCinema = Cubic(0.16, 1.0, 0.3, 1.0);

  // ============ TYPOGRAPHIE ============
  /// Display serif éditorial — titres, héros, chiffres marquants.
  static TextStyle display({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
    FontStyle? fontStyle,
  }) {
    return GoogleFonts.fraunces(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontStyle: fontStyle,
    );
  }

  /// Corps / UI — humaniste chaud, très lisible à distance TV.
  static TextStyle body({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) {
    return GoogleFonts.karla(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  /// Micro-label capitales espacées — « GÉNÉRIQUE DE FILM ».
  static TextStyle eyebrow({
    double fontSize = 11,
    Color color = AppColors.textTertiary,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return GoogleFonts.karla(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 1.6,
      height: 1.1,
      color: color,
    );
  }

  // Alias internes historiques
  static TextStyle _display({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) =>
      display(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );

  static TextStyle _body({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) =>
      body(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );

  // ============ THÈME SOMBRE (principal) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashColor: AppColors.primaryContainer.withValues(alpha: 0.12),
      highlightColor: AppColors.primaryContainer.withValues(alpha: 0.08),

      textTheme: TextTheme(
        // Display — Fraunces, serrée, autoritaire
        displayLarge: _display(
          fontSize: 56,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
          height: 1.02,
        ),
        displayMedium: _display(
          fontSize: 40,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.9,
          height: 1.08,
        ),
        displaySmall: _display(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.15,
        ),
        headlineLarge: _display(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          height: 1.12,
        ),
        headlineMedium: _display(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.2,
        ),
        headlineSmall: _display(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.25,
        ),
        titleLarge: _display(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleMedium: _body(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        titleSmall: _body(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        // Corps — Karla
        bodyLarge: _body(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.62,
          color: AppColors.onSurfaceVariant,
        ),
        bodyMedium: _body(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.55,
          color: AppColors.onSurfaceVariant,
        ),
        bodySmall: _body(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: AppColors.onSurfaceVariant,
        ),
        // Labels — capitales espacées, esprit générique de film
        labelLarge: _body(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1.2,
        ),
        labelMedium: _body(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          height: 1.2,
        ),
        labelSmall: _body(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
          height: 1.2,
          color: AppColors.textTertiary,
        ),
      ),

      // AppBar : plate, sans élévation, le fond fait le travail
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: _display(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),

      // Champs : creusés dans la surface, liseré ember au focus
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
          borderSide:
              const BorderSide(color: AppColors.primaryContainer, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: _body(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.textTertiary,
        ),
        labelStyle: eyebrow(color: AppColors.onSurfaceVariant),
        floatingLabelStyle: eyebrow(color: AppColors.primary),
      ),

      // Boutons pleins : ember franc, coins nets
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryFill,
          foregroundColor: AppColors.onSurface,
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: _body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.black.withValues(alpha: 0.18);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.onSurface.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceContainerHigh,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: _body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),

      // Boutons contour : liseré crème discret
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: _body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: _body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.onSurfaceVariant,
          hoverColor: AppColors.primaryContainer.withValues(alpha: 0.14),
          highlightColor: AppColors.primaryContainer.withValues(alpha: 0.2),
        ),
      ),

      // Cartes : surface opaque + ombre profonde (zéro blur)
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.glassLevel1Border, width: 1),
        ),
      ),

      // Dialogues : bloc opaque flottant
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: AppColors.glassLevel2Border, width: 1),
        ),
        titleTextStyle: _display(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        contentTextStyle: _body(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.55,
          color: AppColors.onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceContainerHighest,
        contentTextStyle: _body(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
        actionTextColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // Chips : étiquettes de bobine
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        deleteIconColor: AppColors.onSurfaceVariant,
        disabledColor: AppColors.surfaceContainer,
        selectedColor: AppColors.primaryFill,
        secondarySelectedColor: AppColors.primaryFill,
        checkmarkColor: AppColors.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: const BorderSide(color: AppColors.outlineVariant, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelStyle: _body(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.onSurfaceVariant,
        ),
        secondaryLabelStyle: _body(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.onSurface,
        ),
      ),

      // Onglets : soulignement ember épais
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.onSurface,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: AppColors.primaryContainer,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: _body(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        unselectedLabelStyle: _body(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        indicatorColor: AppColors.primaryContainer.withValues(alpha: 0.22),
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(color: AppColors.textTertiary),
        selectedLabelTextStyle: eyebrow(color: AppColors.primary),
        unselectedLabelTextStyle: eyebrow(color: AppColors.textTertiary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primaryContainer.withValues(alpha: 0.22),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => eyebrow(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textTertiary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textTertiary,
            size: 24,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.outlineVariant),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(2),
        thickness: WidgetStateProperty.all(5),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryContainer,
        linearTrackColor: AppColors.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryContainer,
        inactiveTrackColor: AppColors.surfaceContainerHigh,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primaryContainer.withValues(alpha: 0.18),
        trackHeight: 4,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onSurface;
          return AppColors.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryContainer;
          }
          return AppColors.surfaceContainerHigh;
        }),
        trackOutlineColor:
            WidgetStateProperty.all(AppColors.outlineVariant),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryContainer;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.onSurface),
        side: const BorderSide(color: AppColors.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        textStyle: _body(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: AppColors.onSurfaceVariant,
        textColor: AppColors.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
        textStyle: _body(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ============ THÈME CLAIR (« papier kraft ») ============
  static ThemeData get lightTheme {
    final scheme = AppColors.lightColorScheme;
    return ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.karlaTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
