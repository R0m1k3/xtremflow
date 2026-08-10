import 'package:flutter/material.dart';

/// XtremFlow — "Warm Cinema" Design System
///
/// Palette: charbon chaud + crème + orange brûlé (ember).
/// Inspiration: salle de projection, pellicule, affiches 70s.
///
/// Règle de perf : AUCUNE couleur de surface n'est translucide.
/// Les anciennes "glass" surfaces sont désormais opaques et pré-teintées,
/// ce qui supprime tout besoin de `BackdropFilter` (killer de perf sur
/// Flutter Web). La profondeur vient des ombres et du contraste, pas du flou.
class AppColors {
  AppColors._();

  // ============ COMPATIBILITY ALIASES ============
  static Color get focusColor => primaryContainer;
  static Color get border => outlineVariant;

  // ============ SURFACE / ON SURFACE ============
  static const Color onSurface = Color(0xFFF3E9DF); // crème
  static const Color onSurfaceVariant = Color(0xFFC5B3A5); // crème atténué

  // ============ BASE LEVEL 0 ============
  /// Noir chaud — le "noir de salle", jamais un noir pur bleuté.
  static const Color baseLevel0 = Color(0xFF0B0908);

  // ============ BACKGROUNDS ============
  static const Color background = Color(0xFF100C0A);
  static const Color onBackground = Color(0xFFF3E9DF);

  static const Color surface = Color(0xFF100C0A);
  static const Color surfaceDim = Color(0xFF0B0908);
  static const Color surfaceBright = Color(0xFF3C322C);

  // Surface Containers (hiérarchie Material 3, toutes opaques)
  static const Color surfaceContainerLowest = Color(0xFF070505);
  static const Color surfaceContainerLow = Color(0xFF181310);
  static const Color surfaceContainer = Color(0xFF1F1815);
  static const Color surfaceContainerHigh = Color(0xFF2A211C);
  static const Color surfaceContainerHighest = Color(0xFF352A24);
  static const Color surfaceVariant = Color(0xFF352A24);

  // ============ PRIMARY (Ember / orange brûlé) ============
  static const Color primary = Color(0xFFFFB68C); // texte & icônes sur sombre
  static const Color onPrimary = Color(0xFF521B00);
  static const Color primaryContainer = Color(0xFFD9541F); // remplissage ember
  static const Color onPrimaryContainer = Color(0xFF2B0A00);
  static const Color inversePrimary = Color(0xFFA63B10);

  /// Braise profonde — réservée aux **remplissages portant du texte**.
  /// `primaryContainer` (#D9541F) est trop lumineux : blanc dessus plafonne
  /// vers 3,9:1, sous le seuil AA de 4,5:1 pour du corps de texte. Cette
  /// variante passe le seuil tout en restant la même couleur perçue.
  static const Color primaryFill = Color(0xFFA8360C);
  static const Color primaryFixed = Color(0xFFFFDBC8);
  static const Color primaryFixedDim = Color(0xFFFFB68C);
  static const Color onPrimaryFixed = Color(0xFF360F00);
  static const Color onPrimaryFixedVariant = Color(0xFF7A2C08);

  // ============ SECONDARY (Terre cuite / argile) ============
  static const Color secondary = Color(0xFFE7C3AC);
  static const Color onSecondary = Color(0xFF442A1B);
  static const Color secondaryContainer = Color(0xFF5D4030);
  static const Color onSecondaryContainer = Color(0xFFFFDCC8);
  static const Color secondaryFixed = Color(0xFFFFDCC8);
  static const Color secondaryFixedDim = Color(0xFFE7C3AC);
  static const Color onSecondaryFixed = Color(0xFF2B160A);
  static const Color onSecondaryFixedVariant = Color(0xFF5D4030);

  // ============ TERTIARY (Laiton / doré patiné) ============
  static const Color tertiary = Color(0xFFD9C88C);
  static const Color onTertiary = Color(0xFF3A3016);
  static const Color tertiaryContainer = Color(0xFF52472A);
  static const Color onTertiaryContainer = Color(0xFFF6E4A6);
  static const Color tertiaryFixed = Color(0xFFF6E4A6);
  static const Color tertiaryFixedDim = Color(0xFFD9C88C);
  static const Color onTertiaryFixed = Color(0xFF231B04);
  static const Color onTertiaryFixedVariant = Color(0xFF52472A);

  // ============ ERROR ============
  static const Color error = Color(0xFFFFB4A6);
  static const Color onError = Color(0xFF5F1409);
  static const Color errorContainer = Color(0xFF8C2416);
  static const Color onErrorContainer = Color(0xFFFFDAD4);

  // ============ OUTLINE ============
  static const Color outline = Color(0xFF9C8878);
  static const Color outlineVariant = Color(0xFF4A3C33);

  // ============ INVERSE SURFACE ============
  static const Color inverseSurface = Color(0xFFF3E9DF);
  static const Color inverseOnSurface = Color(0xFF2A211C);

  // ============ SURFACE TINT ============
  static const Color surfaceTint = Color(0xFFFFB68C);

  // ============ TEXT / CONTENT ============
  static const Color textPrimary = Color(0xFFF3E9DF);
  static const Color textSecondary = Color(0xFFC5B3A5);
  static const Color textTertiary = Color(0xFF9C8878);

  // ============ CRÈME À OPACITÉ (remplace les Colors.whiteNN) ============
  // Déclarés `const` pour rester utilisables dans les widgets constants.
  // Un blanc pur sur fond chaud tire vers le bleu : on décline la crème.
  static const Color onSurface06 = Color(0x0FF3E9DF);
  static const Color onSurface12 = Color(0x1FF3E9DF);
  static const Color onSurface24 = Color(0x3DF3E9DF);
  static const Color onSurface38 = Color(0x61F3E9DF);
  static const Color onSurface54 = Color(0x8AF3E9DF);

  // ============ STATUS ============
  static const Color success = Color(0xFF9BC46A); // olive lumineux
  static const Color warning = Color(0xFFE9B23C); // ambre
  static const Color info = Color(0xFFA3B8C4); // bleu-gris fumé

  // ============ CATÉGORIES ============
  static const Color live = Color(0xFFE5484D); // rouge enseigne
  static const Color movies = Color(0xFFD9541F); // ember
  static const Color series = Color(0xFFD9C88C); // laiton

  // ============ RATING / PREMIUM ============
  static const Color ratingGold = Color(0xFFE9B23C);
  static const Color premiumGold = Color(0xFFC9922A);

  // ============ SHIMMER (placeholders de chargement) ============
  static const Color shimmer = Color(0xFF2A211C);
  static const Color shimmerHighlight = Color(0xFF3C302A);

  // ============ SURFACES "GLASS" — désormais OPAQUES ============
  // Noms conservés pour compatibilité avec les 33 sites d'appel existants.
  // Plus aucune transparence : zéro BackdropFilter, zéro repaint coûteux.
  static const Color glassLevel1Bg = Color(0xFF181310);
  static const Color glassLevel1Border = Color(0x14F3E9DF); // crème 8 %

  static const Color glassLevel2Bg = Color(0xFF1F1815);
  static const Color glassLevel2Border = Color(0x1FF3E9DF); // crème 12 %
  static const Color glassLevel2InnerGlow = Color(0x3DD9541F); // ember 24 %

  // ============ GRADIENTS ============
  /// Braise : orange brûlé vers rouge profond.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFE9701F), Color(0xFFC13A1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Fond de salle : projecteur chaud en haut, obscurité en bas.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF1A1310), Color(0xFF0B0908)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Voile d'affiche : lecture du texte par-dessus une jaquette.
  static const LinearGradient posterScrim = LinearGradient(
    colors: [Color(0x000B0908), Color(0xCC0B0908), Color(0xFF0B0908)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Voile latéral pour les héros pleine largeur.
  static const LinearGradient heroScrim = LinearGradient(
    colors: [Color(0xF20B0908), Color(0x990B0908), Color(0x000B0908)],
    stops: [0.0, 0.45, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ============ GLOW / OMBRES ============
  static Color glowPrimary(double opacity) =>
      const Color(0xFFD9541F).withValues(alpha: opacity);
  static Color glowPrimaryDim(double opacity) =>
      const Color(0xFFFFB68C).withValues(alpha: opacity);

  /// Ombre portée « projecteur » : profonde, chaude, jamais grise.
  static List<BoxShadow> lift({double intensity = 1.0}) => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.55 * intensity),
          blurRadius: 28 * intensity,
          spreadRadius: -8,
          offset: Offset(0, 12 * intensity),
        ),
      ];

  /// Halo ember pour l'élément focalisé (navigation TV / télécommande).
  static List<BoxShadow> emberFocus({double intensity = 1.0}) => [
        BoxShadow(
          color: const Color(0xFFD9541F).withValues(alpha: 0.45 * intensity),
          blurRadius: 32 * intensity,
          spreadRadius: -4,
        ),
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.6),
          blurRadius: 24,
          spreadRadius: -10,
          offset: const Offset(0, 14),
        ),
      ];

  // ============ COLOR SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        surfaceTint: surfaceTint,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        inversePrimary: inversePrimary,
        brightness: Brightness.dark,
      );

  /// Thème clair : « papier kraft » — même famille chaude, inversée.
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Color(0xFFA63B10),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFDBC8),
        onPrimaryContainer: Color(0xFF360F00),
        secondary: Color(0xFF765847),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFFDCC8),
        onSecondaryContainer: Color(0xFF2B160A),
        tertiary: Color(0xFF6A5F3F),
        onTertiary: Colors.white,
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD4),
        onErrorContainer: Color(0xFF410E05),
        surface: Color(0xFFFBF3EC),
        onSurface: Color(0xFF201A16),
        onSurfaceVariant: Color(0xFF52443B),
        outline: Color(0xFF847369),
        outlineVariant: Color(0xFFD6C3B7),
        brightness: Brightness.light,
      );
}
