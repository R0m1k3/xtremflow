import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'glass.dart';

/// Decoration helpers — « Salle obscure ».
///
/// Flat, opaque surfaces from one neutral ramp. No gradients, no glow, no
/// white rims: depth comes from surface steps, and the only shadow sits under
/// the focused element.
class AppDecorations {
  AppDecorations._();

  // ─── Backgrounds ────────────────────────────────────────────────────────────

  /// Page background of the tab content areas.
  static BoxDecoration background(BuildContext context) =>
      const BoxDecoration(color: AppColors.background);

  // ─── Cards ───────────────────────────────────────────────────────────────────

  /// Resting card: a surface step, nothing else.
  static BoxDecoration card({double radius = 14}) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
  );

  /// The lit card: focused on TV.
  static BoxDecoration focused({double radius = 14}) => BoxDecoration(
    color: AppColors.focus,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [AppColors.focusShadow],
  );

  /// TV card: blur-free glass (see [GlassDecoration]). Lit, it becomes
  /// the frosted white card; `AnimatedContainer` blends the two.
  static Decoration tvCard({required bool lit, double radius = 14}) =>
      GlassDecoration(lit: lit ? 1 : 0, radius: radius);

  /// Dark tile behind a channel logo. Stays dark when its card is lit, so
  /// the logo keeps its own colours. [inset]: sunk into a TV card.
  static BoxDecoration logoTile({double radius = 6, bool inset = false}) =>
      BoxDecoration(
        color: inset ? const Color(0xFF15161A) : AppColors.surfaceHigh,
        border: inset ? Border.all(color: const Color(0x1AFFFFFF)) : null,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Kept for older call sites: now the flat [card].
  static BoxDecoration glossyCard(BuildContext context, {double radius = 14}) =>
      card(radius: radius);

  /// Kept for older call sites: draws nothing.
  static BoxDecoration glossShimmer(
    BuildContext context, {
    double radius = 14,
  }) => const BoxDecoration();

  /// Area behind a channel logo inside a card.
  static BoxDecoration channelCardBase(BuildContext context) =>
      const BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      );

  /// Kept for older call sites (the top pill navigation is gone).
  static BoxDecoration navPill(BuildContext context) => const BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  // ─── Search Bar ──────────────────────────────────────────────────────────────

  static BoxDecoration searchBar(BuildContext context) => const BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  // ─── Colours ─────────────────────────────────────────────────────────────────

  static Color textPrimary(BuildContext context) => AppColors.textPrimary;

  static Color textSecondary(BuildContext context) => AppColors.textSecondary;

  static Color iconMuted(BuildContext context) => AppColors.textMuted;

  static Color divider(BuildContext context) => AppColors.hairline;
}
