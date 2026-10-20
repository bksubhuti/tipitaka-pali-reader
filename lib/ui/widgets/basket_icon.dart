import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A woven basket, for the library's basket view: a piṭaka is a basket.
///
/// Drawn rather than taken from the icon font, whose only basket is a
/// shopping basket. Sized and coloured like an [Icon], from [IconTheme]
/// unless given, so it sits among the other view icons as one of them.
class BasketIcon extends StatelessWidget {
  const BasketIcon({super.key, this.size, this.color, this.semanticLabel});

  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: side,
        child: CustomPaint(
            painter: _BasketPainter(color ?? theme.color ?? Colors.black)),
      ),
    );
  }
}

class _BasketPainter extends CustomPainter {
  _BasketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Laid out on a 24-unit grid, as Material icons are.
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The handle, a half-ellipse rising from the rim.
    canvas.drawArc(
        const Rect.fromLTRB(6, 2.5, 18, 20), math.pi, math.pi, false, pen);

    // The rim.
    canvas.drawRRect(
        RRect.fromLTRBR(2.5, 10.5, 21.5, 13.5, const Radius.circular(1.5)),
        pen);

    // The bowl, narrowing to its base.
    final bowl = Path()
      ..moveTo(4.2, 13.5)
      ..quadraticBezierTo(4.8, 21, 8.2, 21)
      ..lineTo(15.8, 21)
      ..quadraticBezierTo(19.2, 21, 19.8, 13.5);
    canvas.drawPath(bowl, pen);

    // The weave: one band across and three ribs down.
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(5.2, 17.3), const Offset(18.8, 17.3), thin);
    canvas.drawLine(const Offset(8.6, 13.5), const Offset(9.6, 21), thin);
    canvas.drawLine(const Offset(12, 13.5), const Offset(12, 21), thin);
    canvas.drawLine(const Offset(15.4, 13.5), const Offset(14.4, 21), thin);
  }

  @override
  bool shouldRepaint(_BasketPainter old) => old.color != color;
}
