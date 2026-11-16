import 'package:flutter/material.dart';

import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/core/theme/app_theme.dart';

/// The XtremFlow mark drawn in vector, without the app icon's dark plate:
/// the play button in the logo's blues, its shine, and the three speed lines.
/// Same geometry as `assets/branding/icon_foreground.svg`. Sits directly on
/// the page, so it belongs to it instead of looking pasted on.
class XtremFlowMark extends StatelessWidget {
  const XtremFlowMark({super.key, this.height = 28});

  /// Height of the mark; the width follows (about 1.4 × the height).
  final double height;

  static const double _aspect = (93 - -4) / (85 - 15); // _MarkPainter.box

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'XtremFlow',
    child: CustomPaint(
      size: Size(height * _aspect, height),
      painter: const _MarkPainter(),
    ),
  );
}

/// Mark + name, "Xtrem" in white and "Flow" in the logo's light blue.
class XtremFlowWordmark extends StatelessWidget {
  const XtremFlowWordmark({
    super.key,
    this.markHeight = 26,
    this.fontSize = 19,
  });

  final double markHeight;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.body(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      letterSpacing: -0.2,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        XtremFlowMark(height: markHeight),
        SizedBox(width: markHeight * .38),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Xtrem'),
              TextSpan(
                text: 'Flow',
                style: style.copyWith(color: AppColors.accent),
              ),
            ],
          ),
          style: style,
        ),
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  /// The glyph's bounds in the SVG's units (strokes and round caps included).
  static const box = Rect.fromLTRB(-4, 15, 93, 85);

  // The logo's blues: light end, deep end, and a darker step of the deep
  // blue for the bottom of the triangle.
  static const _light = AppColors.accent;
  static const _deep = AppColors.accentStrong;
  static const _deeper = Color(0xFF0A5BD6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / box.height;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-box.left, -box.top);

    // Speed lines, fading in from the left.
    final streak = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7
      ..shader = const LinearGradient(colors: [Color(0x008FCFFF), _light])
          .createShader(const Rect.fromLTRB(0, 0, 28, 1));
    canvas
      ..drawLine(const Offset(6, 38), const Offset(28, 38), streak)
      ..drawLine(const Offset(0, 50), const Offset(28, 50), streak)
      ..drawLine(const Offset(10, 62), const Offset(28, 62), streak);

    // The play button: filled and stroked with round joins (soft corners).
    final triangle = Path()
      ..moveTo(40, 22)
      ..lineTo(84, 50)
      ..lineTo(40, 78)
      ..close();
    final play = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-.6, -1),
        end: Alignment(.8, 1),
        stops: [0, .55, 1],
        colors: [_light, _deep, _deeper],
      ).createShader(const Rect.fromLTRB(34, 16, 90, 84));
    canvas
      ..drawPath(triangle, play)
      ..drawPath(
        triangle,
        Paint()
          ..shader = play.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeJoin = StrokeJoin.round,
      );

    // Shine along the top edge.
    canvas.drawLine(
      const Offset(44, 34),
      const Offset(66, 48),
      Paint()
        ..color = const Color(0x47FFFFFF)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
