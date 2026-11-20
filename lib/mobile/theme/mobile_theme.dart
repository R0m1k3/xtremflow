import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Thème téléphone XtremFlow — « Salle obscure ».
///
/// Le thème de l'application ([AppTheme.darkTheme] : jetons [AppColors],
/// Figtree, barre de navigation `surface` + indicateur `accentFill`), avec
/// des cibles tactiles plus généreuses. Aucune palette propre.
class MobileTheme {
  MobileTheme._();

  // ============ ESPACEMENT ============
  static const double spacingXs = AppTheme.spacing4;
  static const double spacingSm = AppTheme.spacing8;
  static const double spacingMd = AppTheme.spacing16;
  static const double spacingLg = AppTheme.spacing24;
  static const double spacingXl = AppTheme.spacing32;

  // ============ RAYONS (ceux d'AppTheme) ============
  static const double radiusSm = AppTheme.radiusSm;
  static const double radiusMd = AppTheme.radiusMd;
  static const double radiusLg = AppTheme.radiusLg;
  static const double radiusXl = AppTheme.radiusXl;

  // ============ THÈME SOMBRE (le seul) ============
  static ThemeData get darkTheme {
    final base = AppTheme.darkTheme;

    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.background,
        centerTitle: false,
        titleTextStyle: AppTheme.display(fontSize: 20),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.accentFill,
        disabledColor: AppColors.surface,
        side: BorderSide.none,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        labelStyle: AppTheme.body(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: AppTheme.body(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        minVerticalPadding: 12,
        titleTextStyle: AppTheme.body(
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: AppTheme.body(
          fontSize: 13,
          color: AppColors.textMuted,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusField),
        ),
        textStyle: AppTheme.body(fontSize: 15),
      ),
    );
  }
}
