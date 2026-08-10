import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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

  bool get _showBorder => hasBorder ?? border;

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
    switch (level) {
      case GlassLevel.level0:
        return _buildLevel0();
      case GlassLevel.level1:
        return _buildLevel1();
      case GlassLevel.level2:
        return _buildLevel2();
    }
  }

  Widget _buildLevel0() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.baseLevel0,
        borderRadius: BorderRadius.circular(borderRadius),
        border: _showBorder
            ? Border.all(
                color: borderColor ?? Colors.transparent,
                width: 1,
              )
            : null,
        boxShadow: showShadow ? boxShadow : null,
      ),
      child: child,
    );
  }

  Widget _buildLevel1() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.glassLevel1Bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: _showBorder
            ? Border.all(
                color: borderColor ?? AppColors.glassLevel1Border,
                width: 1,
              )
            : null,
        boxShadow: !showShadow
            ? null
            : boxShadow ??
            const [
              BoxShadow(
                color: Color(0x59000000), // noir 35 %
                blurRadius: 18,
                spreadRadius: -6,
                offset: Offset(0, 8),
              ),
            ],
      ),
      child: child,
    );
  }

  Widget _buildLevel2() {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        // Dégradé très court : arête haute captant la « lumière du projecteur ».
        gradient: const LinearGradient(
          colors: [Color(0xFF262019), Color(0xFF1F1815)],
          stops: [0.0, 0.45],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: _showBorder
            ? Border(
                top: BorderSide(
                  color: borderColor ?? AppColors.glassLevel2InnerGlow,
                  width: 1,
                ),
                left: BorderSide(
                  color: borderColor ?? AppColors.glassLevel2Border,
                  width: 1,
                ),
                right: BorderSide(
                  color: borderColor ?? AppColors.glassLevel2Border,
                  width: 1,
                ),
                bottom: BorderSide(
                  color: borderColor ?? AppColors.glassLevel2Border,
                  width: 1,
                ),
              )
            : null,
        boxShadow: !showShadow
            ? null
            : boxShadow ??
            const [
              BoxShadow(
                color: Color(0xA6000000), // noir 65 %
                blurRadius: 40,
                spreadRadius: -12,
                offset: Offset(0, 20),
              ),
              BoxShadow(
                color: Color(0x1FD9541F), // halo ember 12 %
                blurRadius: 48,
                spreadRadius: -18,
              ),
            ],
      ),
      child: child,
    );
  }
}

/// Carte de surface interactive — variante cliquable de [GlassContainer].
///
/// Survol : la carte se soulève et son liseré passe à la braise.
/// Focus clavier / télécommande : halo ember net, indispensable en usage TV.
class GlassCard extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final GlassLevel level;

  /// Active les réactions au survol et au focus.
  final bool interactive;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14.0,
    this.level = GlassLevel.level1,
    this.interactive = false,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => widget.interactive && (_hovered || _focused);

  @override
  Widget build(BuildContext context) {
    final surface = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.level == GlassLevel.level0
            ? AppColors.baseLevel0
            : (_active
                ? AppColors.surfaceContainerHigh
                : AppColors.glassLevel1Bg),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: _active
              ? AppColors.primaryContainer
              : AppColors.glassLevel1Border,
          width: _active ? 2 : 1,
        ),
        boxShadow: _active
            ? AppColors.emberFocus()
            : const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      // Le contenu est rogné pour que les affiches épousent le rayon.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          (widget.borderRadius - 1).clamp(0.0, widget.borderRadius),
        ),
        child: widget.child,
      ),
    );

    if (!widget.interactive && widget.onTap == null) return surface;

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: surface,
      ),
    );
  }
}

/// Fond de scène « Warm Cinema ».
///
/// Dégradé chaud + vignettage, sans image ni flou. Sert de toile de fond aux
/// écrans principaux pour éviter les aplats plats et sans atmosphère.
class CinemaBackdrop extends StatelessWidget {
  final Widget child;

  /// Halo ember diffus en haut à gauche (lueur de projection).
  final bool projectorGlow;

  const CinemaBackdrop({
    super.key,
    required this.child,
    this.projectorGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: projectorGlow
          ? Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.75, -0.95),
                        radius: 1.25,
                        colors: [
                          AppColors.primaryContainer.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                // Vignettage bas : ancre le contenu, style projection.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child,
              ],
            )
          : child,
    );
  }
}
