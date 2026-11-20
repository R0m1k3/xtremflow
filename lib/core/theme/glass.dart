import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Image, PixelFormat, decodeImageFromPixels;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Glass without blur.
///
/// A real frosted glass (`BackdropFilter`) re-blurs what is behind it on
/// every frame and is the first thing to drop frames on a Fire TV. Here the
/// page behind the cards is a few soft blue glows ([AmbientBackground]) that
/// look the same blurred or not, so a translucent fill is enough to read as
/// frosted glass: lighter at the top left, a breath of the logo's blue at the
/// bottom right, and a rim lit from the top left that cools to blue.
///
/// Cost matters more than anything here: with a live preview playing, the
/// TV redraws the whole screen for every video frame. So a card is exactly
/// two draws (one gradient body, one gradient rim), no clip, no layer, and
/// no blurred shadow: the lit card's blue halo is a few plain strokes.
///
/// [lit] goes from 0 (resting glass) to 1 (the lit card: frosted white, dark
/// ink on it). `AnimatedContainer` blends between the two.
///
/// [bare]: nothing at rest, glass only when lit (rows of a list).
/// [halo]: the blue halo around the lit card (off where items are packed).
class GlassDecoration extends Decoration {
  const GlassDecoration({
    this.lit = 0,
    this.radius = 14,
    this.bare = false,
    this.halo = true,
  });

  final double lit;
  final double radius;
  final bool bare;
  final bool halo;

  static GlassDecoration lerp(GlassDecoration a, GlassDecoration b, double t) =>
      GlassDecoration(
        lit: lerpDouble(a.lit, b.lit, t)!,
        radius: lerpDouble(a.radius, b.radius, t)!,
        bare: b.bare,
        halo: b.halo,
      );

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is GlassDecoration ? lerp(a, this, t) : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is GlassDecoration ? lerp(this, b, t) : super.lerpTo(b, t);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ).contains(position);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GlassPainter(this);

  @override
  bool operator ==(Object other) =>
      other is GlassDecoration &&
      other.lit == lit &&
      other.radius == radius &&
      other.bare == bare &&
      other.halo == halo;

  @override
  int get hashCode => Object.hash(lit, radius, bare, halo);
}

class _GlassPainter extends BoxPainter {
  _GlassPainter(this.d);
  final GlassDecoration d;

  // Body, top left to bottom right: light, then the logo's blue pooling.
  // No glint at rest: the same streak on every card read as generated gloss.
  static const _stops = [0.0, .45, 1.0];
  static const _rest = [
    Color(0x29FFFFFF),
    Color(0x17FFFFFF),
    Color(0x2E0A82FD),
  ];
  static const _bare = [
    Color(0x00FFFFFF),
    Color(0x00FFFFFF),
    Color(0x000A82FD),
  ];
  static const _lit = [AppColors.focusTop, Color(0xFFEEEDEA), AppColors.focus];

  // Rim: lit top left, dim middle, light blue bottom right.
  static const _rimRest = [
    Color(0x66FFFFFF),
    Color(0x14FFFFFF),
    Color(0x598FCFFF),
  ];
  static const _rimBare = [
    Color(0x00FFFFFF),
    Color(0x00FFFFFF),
    Color(0x008FCFFF),
  ];
  static const _rimLit = [
    Color(0xFFFFFFFF),
    Color(0x99FFFFFF),
    Color(0xCC8FCFFF),
  ];

  // Lit halo: plain strokes, fading outwards (a blur would cost a pass).
  // 8 dp at most: with the 1.05 zoom it stays clear of the next card.
  static const _halo = [(2.0, .55), (5.0, .25), (8.0, .08)];

  static List<Color> _mix(List<Color> a, List<Color> b, double t) => [
    for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
  ];

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final l = d.lit.clamp(0.0, 1.0);
    if (d.bare && l == 0) return;
    final rect = offset & size;
    final r = d.radius.clamp(0.0, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    if (l > 0 && d.halo) {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (final (out, alpha) in _halo) {
        halo.color = AppColors.accentStrong.withValues(alpha: alpha * l);
        canvas.drawRRect(rrect.inflate(out - 1.5), halo);
      }
    }

    final rest = d.bare ? _bare : _rest;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: _stops,
          colors: l == 0 ? rest : _mix(rest, _lit, l),
        ).createShader(rect),
    );

    final rimRest = d.bare ? _rimBare : _rimRest;
    const w = 1.2;
    canvas.drawRRect(
      rrect.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: _stops,
          colors: l == 0 ? rimRest : _mix(rimRest, _rimLit, l),
        ).createShader(rect),
    );
  }
}

/// Page background: near-black with soft light in the logo's blue, from the
/// top left and the bottom right. The glass cards show it through.
///
/// Computed once, pixel by pixel, into a 640×360 image that is stretched to
/// the screen: one textured draw per frame instead of full-screen gradients.
/// A grain of ±1.5 levels is added to every pixel: dark gradients over 8-bit
/// TV panels (and Fire TV's limited-range HDMI) otherwise show as rings.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  static final ValueNotifier<ui.Image?> _image = ValueNotifier(null);
  static bool _started = false;

  static void _bake() {
    if (_started) return;
    _started = true;
    compute(_ambientPixels, null).then((pixels) {
      ui.decodeImageFromPixels(
        pixels,
        _ambientW,
        _ambientH,
        ui.PixelFormat.rgba8888,
        (image) => _image.value = image,
      );
    });
  }

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  @override
  void initState() {
    super.initState();
    AmbientBackground._bake();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: AmbientBackground._image,
          builder: (context, image, _) =>
              CustomPaint(painter: _AmbientPainter(image)),
        ),
      ),
      widget.child,
    ],
  );
}

const _ambientW = 640, _ambientH = 360;

/// The glows: centre (fraction of width / height), radius (fraction of the
/// width), colour and peak opacity. Two hues only, the logo's.
const _glows = [
  // Behind the logo, top left: the logo's deep blue.
  (.10, -.10, .55, 0x0A, 0x82, 0xFD, .30),
  // Bottom right, the same blue, quieter.
  (1.0, 1.10, .60, 0x0A, 0x82, 0xFD, .20),
  // A faint light blue in the middle, so the glass has something to catch.
  (.62, .42, .38, 0x8F, 0xCF, 0xFF, .07),
];

/// RGBA pixels of the ambient background (runs in an isolate).
Uint8List _ambientPixels(void _) {
  const w = _ambientW, h = _ambientH;
  final out = Uint8List(w * h * 4);
  final rnd = math.Random(7);
  const base = AppColors.background;
  final br = base.r * 255, bg = base.g * 255, bb = base.b * 255;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = br, g = bg, b = bb;
      for (final (cx, cy, rad, gr, gg, gb, peak) in _glows) {
        final dx = x - cx * w, dy = y - cy * h;
        final t = math.sqrt(dx * dx + dy * dy) / (rad * w);
        if (t >= 1) continue;
        final a = peak * (1 - t);
        r = r + (gr - r) * a;
        g = g + (gg - g) * a;
        b = b + (gb - b) * a;
      }
      final noise = (rnd.nextDouble() - .5) * 3;
      final i = (y * w + x) * 4;
      out[i] = (r + noise).round().clamp(0, 255);
      out[i + 1] = (g + noise).round().clamp(0, 255);
      out[i + 2] = (b + noise).round().clamp(0, 255);
      out[i + 3] = 255;
    }
  }
  return out;
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.image);
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppColors.background,
      );
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) => oldDelegate.image != image;
}
