import 'package:flutter/material.dart';

/// The X-ray icon: a figure holding a screen that shows its spine and ribs.
/// Without [screen], the figure alone, for X-ray turned off.
///
/// Drawn here rather than taken from an icon set, which has nothing like it,
/// or from stock art, which is licensed. It takes its size and colour from
/// the surrounding [IconTheme], as an [Icon] does.
class XrayIcon extends StatelessWidget {
  const XrayIcon({super.key, this.size, this.color, this.screen = true});

  final double? size;
  final Color? color;
  final bool screen;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _XrayPainter(color ?? theme.color ?? Colors.black, screen),
      ),
    );
  }
}

class _XrayPainter extends CustomPainter {
  _XrayPainter(this.color, this.screen);

  final Color color;
  final bool screen;

  @override
  void paint(Canvas canvas, Size size) {
    // Laid out on a 24-unit grid, like Material icons, and scaled.
    canvas.scale(size.width / 24, size.height / 24);
    // Its own layer, so clearing the screen's inside clears only the figure
    // behind it, not whatever the icon is drawn on. The figure is drawn solid
    // and the colour's transparency put on the layer as a whole: drawn with
    // it, the places where the shapes overlap came out darker.
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24),
        Paint()..color = Colors.black.withValues(alpha: color.a));
    final solid = color.withValues(alpha: 1);
    final fill = Paint()..color = solid;
    final line = Paint()
      ..color = solid
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Head.
    canvas.drawCircle(const Offset(12, 4.2), 3, fill);

    // Shoulders and arms, behind the screen.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTRB(4.5, 8.2, 19.5, 15),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      fill,
    );

    // Legs below the screen.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTRB(8.6, 18, 11.4, 23.2), const Radius.circular(1.4)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTRB(12.6, 18, 15.4, 23.2), const Radius.circular(1.4)),
      fill,
    );

    if (!screen) {
      // No screen: the body, from the shoulders down to the legs.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTRB(7.2, 12, 16.8, 18.6),
          bottomLeft: const Radius.circular(1.6),
          bottomRight: const Radius.circular(1.6),
        ),
        fill,
      );
      canvas.restore();
      return;
    }

    // The screen: a frame with a clear inside, so the ribs show.
    final frame = RRect.fromRectAndRadius(
        const Rect.fromLTRB(5.5, 9.5, 18.5, 19.5), const Radius.circular(1.6));
    canvas.drawRRect(frame, fill);
    canvas.drawRRect(
      frame.deflate(1.5),
      Paint()..blendMode = BlendMode.clear,
    );

    // Spine and ribs.
    line.strokeWidth = 1.2;
    canvas.drawLine(const Offset(12, 11.6), const Offset(12, 17.6), line);
    for (final (y, half) in [(12.2, 2.7), (14.0, 3.1), (15.8, 2.7)]) {
      final rib = Path()
        ..moveTo(12 - half, y + 0.7)
        ..quadraticBezierTo(12, y - 0.9, 12 + half, y + 0.7);
      canvas.drawPath(rib, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_XrayPainter old) =>
      old.color != color || old.screen != screen;
}
