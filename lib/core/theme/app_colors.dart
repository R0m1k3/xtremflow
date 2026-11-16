import 'package:flutter/material.dart';

/// XtremFlow — « Salle obscure » design system.
///
/// The living room at night, lights off: the screen is the only light. The
/// chrome is a neutral graphite ramp and stays quiet; channel logos and
/// posters carry the colour. One thing is lit at a time — the focused item
/// ([focus]) — and one accent exists: [live], the red "on air" line that shows
/// how far the current programme has run. Nothing else is red.
///
/// A touch of light blue, the blue of the XtremFlow logo, marks what is
/// "yours" or "here": the current tab, favourite stars, the card edges.
///
/// Performance rule: every surface is opaque. Depth comes from surface steps
/// and hairlines, never from blur (`BackdropFilter` repaints every frame and
/// is the first thing to drop frames on low-end Android and Fire TV).
class AppColors {
  AppColors._();

  // ============ RAMP « SALLE OBSCURE » ============
  /// Scaffold / page background.
  static const Color background = Color(0xFF101216);

  /// TV navigation rail, a step below the page.
  static const Color rail = Color(0xFF090A0D);

  /// Cards, panels, bottom bar, text fields.
  static const Color surface = Color(0xFF18181A);

  /// Raised: active destination, selected row, logo tile.
  static const Color surfaceHigh = Color(0xFF232326);

  /// Progress track, the highest neutral step.
  static const Color track = Color(0xFF2E2E31);

  /// TV cards (tvOS-style platters): a lighter top, a darker bottom, and a
  /// light edge so the shape reads on the near-black page.
  static const Color cardTop = Color(0xFF2D2F35);
  static const Color cardBottom = Color(0xFF222328);
  static const Color cardEdge = Color(0x248FCFFF);

  // ============ LIGHT BLUE (the logo's) ============
  // Two blues only, both from the logo: its light end and its deep end.
  /// Light blue on dark: current tab, favourite stars.
  static const Color accent = Color(0xFF8FCFFF);

  /// The logo's deep blue: glows, glass pool, focus halo.
  static const Color accentStrong = Color(0xFF0A82FD);

  /// The deep blue darkened for marks on the lit (light) card: 5:1.
  static const Color accentOnLight = Color(0xFF0060DF);

  /// Tinted fill behind the current tab.
  static const Color accentFill = Color(0x260A82FD);

  // ============ GLASS (see glass.dart) ============
  /// Resting glass: white at 13 % fading to 5 %, over the ambient page.
  static const Color glassTop = Color(0x21FFFFFF);
  static const Color glassBottom = Color(0x0DFFFFFF);

  /// The blue pooling in the bottom-right corner of the glass.
  static const Color glassTint = Color(0x1F0A84FF);

  /// Separators: primary text at 8 %.
  static const Color hairline = Color(0x14EDEDED);

  // Three text roles.
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color textSecondary = Color(0xFFBDBDC2);
  static const Color textMuted = Color(0xFFA8A8AE);

  // The lit element (TV focus).
  static const Color focus = Color(0xFFE9E8E4);

  /// Top of the lit card: a touch brighter, as if lit from above.
  static const Color focusTop = Color(0xFFF4F4F2);
  static const Color onFocus = Color(0xFF111112);
  static const Color onFocusMuted = Color(0xFF55555A);
  static const Color focusTrack = Color(0xFFD4D3CF);

  /// Red "on air": the progress of the programme on now, and nothing else.
  static const Color live = Color(0xFFF0533F);

  /// The same red, darkened to read on the lit (light) card.
  static const Color liveOnLight = Color(0xFFD93A26);

  // ============ MATERIAL ROLES (mapped onto the ramp) ============
  static const Color baseLevel0 = rail;
  static const Color onBackground = textPrimary;
  static const Color headerBackground = background;
  static const Color surfaceDim = rail;
  static const Color surfaceBright = track;

  static const Color surfaceContainerLowest = rail;
  static const Color surfaceContainerLow = surface;
  static const Color surfaceContainer = surface;
  static const Color surfaceContainerHigh = surfaceHigh;
  static const Color surfaceContainerHighest = track;
  static const Color surfaceVariant = surfaceHigh;

  static const Color onSurface = textPrimary;
  static const Color onSurfaceVariant = textSecondary;

  /// No colourful primary any more: primary content is the off-white text,
  /// a filled primary control is the lit surface with dark ink.
  static const Color primary = textPrimary;
  static const Color onPrimary = onFocus;
  static const Color primaryContainer = focus;
  static const Color onPrimaryContainer = onFocus;
  static const Color inversePrimary = onFocus;

  /// Neutral fill that carries light text (selected chips, active nav).
  static const Color primaryFill = track;

  /// Ink for text/icons placed on a light fill.
  static const Color onPrimaryFixed = onFocus;
  static const Color primaryFixed = focus;
  static const Color primaryFixedDim = focusTrack;
  static const Color onPrimaryFixedVariant = onFocusMuted;

  static const Color secondary = textSecondary;
  static const Color onSecondary = onFocus;
  static const Color secondaryContainer = surfaceHigh;
  static const Color onSecondaryContainer = textPrimary;

  static const Color tertiary = textSecondary;
  static const Color onTertiary = onFocus;
  static const Color tertiaryContainer = surfaceHigh;
  static const Color onTertiaryContainer = textPrimary;

  // ============ ERROR ============
  static const Color error = Color(0xFFE5484D);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFF3B1719);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // ============ OUTLINE ============
  static const Color outline = textMuted;
  static const Color outlineVariant = track;

  // ============ INVERSE ============
  static const Color inverseSurface = focus;
  static const Color inverseOnSurface = onFocus;
  static const Color surfaceTint = Color(0x00000000);

  static const Color textTertiary = textMuted;

  // ============ TEXT AT OPACITY ============
  static const Color onSurface06 = Color(0x0FEDEDED);
  static const Color onSurface12 = Color(0x1FEDEDED);
  static const Color onSurface24 = Color(0x3DEDEDED);
  static const Color onSurface38 = Color(0x61EDEDED);
  static const Color onSurface54 = Color(0x8AEDEDED);
  static const Color onSurface70 = Color(0xB3EDEDED);

  // ============ STATUS (toned down to sit in the palette) ============
  static const Color success = Color(0xFF4CAF6E);
  static const Color warning = Color(0xFFD9A441);
  static const Color info = textSecondary;

  // ============ LEGACY PER-TAB COLOURS — now neutral ============
  // One accent only: tabs no longer get their own hue.
  static const Color movies = textSecondary;
  static const Color series = textSecondary;

  // Ratings and favourites are marked in the text colour, not gold.
  static const Color ratingGold = textSecondary;
  static const Color premiumGold = textSecondary;

  // ============ SHIMMER (loading placeholders) ============
  static const Color shimmer = surface;
  static const Color shimmerHighlight = surfaceHigh;

  // ============ BORDERS / FOCUS ============
  static const Color border = track;
  static const Color focusColor = focus;
  static const Color focusBorder = focus;
  static const Color borderFocused = focus;

  static const Color glassBorderColor = hairline;
  static const Color glassLevel1Bg = surface;
  static const Color glassLevel1Border = hairline;
  static const Color glassLevel2Bg = surface;
  static const Color glassLevel2Border = hairline;
  static const Color glassLevel2InnerGlow = Color(0x00000000);
  static const Color glassBackground = surface;
  static const Color glassBorder = hairline;

  // ============ "GRADIENTS" — flat on purpose ============
  // Kept as gradients only so existing call sites compile; each is a single
  // neutral, no hue shift.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [focus, focus],
  );
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [background, background],
  );
  static const RadialGradient projectorGradient = RadialGradient(
    colors: [background, background],
  );
  static const LinearGradient cardGradient = LinearGradient(
    colors: [surface, surface],
  );
  static const LinearGradient cardHighlight = LinearGradient(
    colors: [Color(0x00000000), Color(0x00000000)],
  );

  /// Scrim to read text over artwork.
  static const LinearGradient posterScrim = LinearGradient(
    colors: [Color(0x000E0E0F), Color(0xCC0E0E0F), Color(0xFF0E0E0F)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Side scrim for full-width hero artwork.
  static const LinearGradient heroScrim = LinearGradient(
    colors: [Color(0xF20E0E0F), Color(0x990E0E0F), Color(0x000E0E0F)],
    stops: [0.0, 0.45, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ============ SHADOWS ============
  /// Neutral shadow, only under the focused (lit) element.
  /// The lit card floats above the page.
  static const BoxShadow focusShadow = BoxShadow(
    color: Color(0x66000000),
    blurRadius: 36,
    offset: Offset(0, 12),
  );

  static Color glowPrimary(double opacity) =>
      const Color(0xFF000000).withValues(alpha: opacity);
  static Color glowPrimaryDim(double opacity) =>
      const Color(0xFF000000).withValues(alpha: opacity);

  static List<BoxShadow> lift({double intensity = 1.0}) => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.5 * intensity),
      blurRadius: 24 * intensity,
      offset: Offset(0, 8 * intensity),
    ),
  ];

  /// Historical name kept for call sites: now the plain focus shadow.
  static List<BoxShadow> emberFocus({double intensity = 1.0}) =>
      lift(intensity: intensity);

  // ============ COMPATIBILITY ALIASES ============
  static const Color backgroundSecondary = surface;
  static const Color surfaceElevated = surfaceHigh;
  static const Color appleBlue = primaryFill;

  static const RadialGradient appleTvGradient = projectorGradient;
  static const LinearGradient glossyCardGradient = cardGradient;
  static const LinearGradient glossyHighlight = cardHighlight;
  static const LinearGradient cardGlossyGradient = cardGradient;
  static const LinearGradient cardGlossyHighlight = cardHighlight;

  // ============ ALIASES (xtremflow only) ============
  // Names kept from the former "Warm Cinema" palette so existing callers keep
  // compiling; they map onto the neutral ramp.
  static const Color secondaryFixed = surfaceHigh;
  static const Color secondaryFixedDim = track;
  static const Color onSecondaryFixed = textPrimary;
  static const Color onSecondaryFixedVariant = textSecondary;
  static const Color tertiaryFixed = surfaceHigh;
  static const Color tertiaryFixedDim = track;
  static const Color onTertiaryFixed = textPrimary;
  static const Color onTertiaryFixedVariant = textSecondary;

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
    onInverseSurface: inverseOnSurface,
    inversePrimary: inversePrimary,
    brightness: Brightness.dark,
  );

  /// Light scheme, same neutral family (the IPTV UI forces dark).
  static ColorScheme get lightColorScheme => const ColorScheme.light(
    primary: Color(0xFF111112),
    onPrimary: Color(0xFFF2F1EE),
    primaryContainer: Color(0xFFE4E3E0),
    onPrimaryContainer: Color(0xFF111112),
    secondary: Color(0xFF55555A),
    onSecondary: Color(0xFFF2F1EE),
    secondaryContainer: Color(0xFFE4E3E0),
    onSecondaryContainer: Color(0xFF111112),
    tertiary: Color(0xFF55555A),
    onTertiary: Color(0xFFF2F1EE),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD4),
    onErrorContainer: Color(0xFF410E05),
    surface: Color(0xFFF2F1EE),
    onSurface: Color(0xFF111112),
    onSurfaceVariant: Color(0xFF55555A),
    outline: Color(0xFF85858B),
    outlineVariant: Color(0xFFD4D3CF),
    brightness: Brightness.light,
  );
}
