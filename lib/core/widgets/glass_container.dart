import 'package:flutter/material.dart';

import '../theme/glass.dart';

/// Conteneur de surface « Warm Cinema » — 3 niveaux de profondeur.
///
/// Level 0 : socle brut (#0B0908), aucune ombre.
/// Level 1 : plaque opaque légèrement éclaircie, liseré crème 8 %, ombre douce.
/// Level 2 : bloc flottant, liseré ember sur l'arête haute, ombre profonde.
///
/// PERF : cette version n'utilise **aucun** `BackdropFilter`. Le flou de fond
/// forçait Flutter Web à relire le framebuffer à chaque frame pour chaque
/// carte à l'écran (33 sites d'appel ici) — cause principale du jank au
/// scroll. La profondeur est désormais rendue par des surfaces opaques
/// pré-teintées et des ombres, ce qui coûte quasiment rien au GPU.
///
/// L'API publique est inchangée : aucun site d'appel n'a besoin d'être modifié.
enum GlassLevel { level0, level1, level2 }

/// A pane of « glass without blur » ([GlassDecoration], `glass.dart`).
///
/// The API of the former Warm Cinema container is kept so its callers did not
/// change. The charter has no shadow at rest and no coloured border: [level],
/// [border], [hasBorder], [borderColor], [boxShadow] and [showShadow] are
/// accepted and ignored.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final GlassLevel level;
  final Color? borderColor;
  final bool border;
  final List<BoxShadow>? boxShadow;

  /// Alias de [border] (nom utilisé par les widgets de navigation TV).
  /// Prioritaire sur [border] lorsqu'il est fourni.
  final bool? hasBorder;

  /// Passer `false` supprime toute ombre portée — utile pour les barres
  /// collées à un bord, où l'ombre créerait une couture visible.
  final bool showShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14.0,
    this.level = GlassLevel.level1,
    this.borderColor,
    this.border = true,
    this.boxShadow,
    this.hasBorder,
    this.showShadow = true,
  });

  /// Niveau 0 — socle brut.
  const GlassContainer.base({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14.0,
    this.borderColor,
    this.border = false,
    this.boxShadow,
    this.hasBorder,
    this.showShadow = true,
  }) : level = GlassLevel.level0;

  /// Niveau 1 — plaque standard.
  const GlassContainer.glass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14.0,
    this.borderColor,
    this.border = true,
    this.boxShadow,
    this.hasBorder,
    this.showShadow = true,
  }) : level = GlassLevel.level1;

  /// Niveau 2 — bloc flottant (modales, panneaux, overlays).
  const GlassContainer.floating({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 20.0,
    this.borderColor,
    this.border = true,
    this.boxShadow,
    this.hasBorder,
    this.showShadow = true,
  }) : level = GlassLevel.level2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: GlassDecoration(radius: borderRadius, halo: false),
      child: child,
    );
  }
}
