import 'dart:math';
import 'package:flutter/material.dart';

/// Paints the esoteric geometric hypercube / tesseract linework watermark
/// matching the Murmur design specification.
class HypercubeWatermark extends StatelessWidget {
  final double size;
  final double opacity;

  const HypercubeWatermark({
    super.key,
    this.size = 800,
    this.opacity = 0.045,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: Size(size, size),
          painter: _HypercubePainter(),
        ),
      ),
    );
  }
}

class _HypercubePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 600.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    // Outer polygon
    _drawHexagon(canvas, 160, paint);
    // Inner polygon
    _drawHexagon(canvas, 100, paint);
    // Innermost polygon
    _drawHexagon(canvas, 50, paint..strokeWidth = 1.5);
    paint.strokeWidth = 1.2;

    // Connecting rays
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3 - pi / 2;
      final p1 = Offset(160 * cos(angle), 160 * sin(angle));
      final p2 = Offset(100 * cos(angle), 100 * sin(angle));
      final p3 = Offset(50 * cos(angle), 50 * sin(angle));
      canvas.drawLine(p1, p2, paint);
      canvas.drawLine(p2, p3, paint);

      // Node dots
      canvas.drawCircle(p1, 2.5, dotPaint);
    }

    // Central core dot
    canvas.drawCircle(Offset.zero, 3.5, dotPaint);

    // Orbiting offset isometric sub-cubes
    _drawSubCube(canvas, const Offset(140, -110), 60, paint);
    _drawSubCube(canvas, const Offset(-140, -110), 60, paint);
    _drawSubCube(canvas, const Offset(150, 110), 60, paint);
    _drawSubCube(canvas, const Offset(-150, 110), 60, paint);

    // Horizon line marks
    canvas.drawLine(const Offset(-220, 0), const Offset(-160, 0), paint);
    canvas.drawLine(const Offset(160, 0), const Offset(220, 0), paint);
    canvas.drawLine(const Offset(-180, -15), const Offset(-180, 15), paint);
    canvas.drawLine(const Offset(180, -15), const Offset(180, 15), paint);

    canvas.restore();
  }

  void _drawHexagon(Canvas canvas, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3 - pi / 2;
      final x = radius * cos(angle);
      final y = radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSubCube(Canvas canvas, Offset offset, double r, Paint paint) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _drawHexagon(canvas, r, paint);
    _drawHexagon(canvas, r * 0.55, paint);
    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 + pi / 6;
      canvas.drawLine(Offset.zero, Offset(r * cos(angle), r * sin(angle)), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
