import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen 3 - Connected care: three typographic nodes joined by extremely
/// thin curves. The nodes settle gently into alignment on entry - editorial
/// information design, not a network diagram.
class ConnectedCareVisual extends StatelessWidget {
  const ConnectedCareVisual({super.key});

  // Anchor points as fractions of the canvas.
  static const Offset _patient = Offset(0.26, 0.24);
  static const Offset _caregiver = Offset(0.74, 0.52);
  static const Offset _clinician = Offset(0.30, 0.82);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double t, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size canvas =
                Size(constraints.maxWidth, constraints.maxHeight);
            return CustomPaint(
              painter: _CarePainter(
                progress: ((t - 0.25) / 0.6).clamp(0.0, 1.0),
                lineColor: scheme.onSurfaceVariant,
                anchors: const <Offset>[_patient, _caregiver, _clinician],
              ),
              child: Stack(
                children: <Widget>[
                  _Node(
                    label: 'PATIENT',
                    anchor: _patient,
                    canvas: canvas,
                    appear: _appear(t, 0.00),
                    color: scheme.onSurface,
                  ),
                  _Node(
                    label: 'CAREGIVER',
                    anchor: _caregiver,
                    canvas: canvas,
                    appear: _appear(t, 0.15),
                    color: scheme.onSurface,
                  ),
                  _Node(
                    label: 'CLINICIAN',
                    anchor: _clinician,
                    canvas: canvas,
                    appear: _appear(t, 0.30),
                    color: scheme.onSurface,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static double _appear(double t, double delay) =>
      ((t - delay) / 0.55).clamp(0.0, 1.0);
}

class _Node extends StatelessWidget {
  const _Node({
    required this.label,
    required this.anchor,
    required this.canvas,
    required this.appear,
    required this.color,
  });

  final String label;
  final Offset anchor;
  final Size canvas;
  final double appear;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const double boxWidth = 120;
    const double boxHeight = 22;
    return Positioned(
      left: anchor.dx * canvas.width - boxWidth / 2,
      top: anchor.dy * canvas.height - boxHeight / 2 + (1 - appear) * 10,
      width: boxWidth,
      height: boxHeight,
      child: Opacity(
        opacity: appear,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.8,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarePainter extends CustomPainter {
  const _CarePainter({
    required this.progress,
    required this.lineColor,
    required this.anchors,
  });

  final double progress;
  final Color lineColor;
  final List<Offset> anchors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress <= 0) {
      return;
    }

    final List<Offset> points = anchors
        .map((Offset a) => Offset(a.dx * size.width, a.dy * size.height))
        .toList();

    final Paint paint = Paint()
      ..color = lineColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    // Gently curved connectors between the three nodes.
    final List<(Offset, Offset)> edges = <(Offset, Offset)>[
      (points[0], points[1]),
      (points[1], points[2]),
      (points[0], points[2]),
    ];

    for (final (Offset a, Offset b) in edges) {
      final Offset mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final double dx = b.dx - a.dx;
      final double dy = b.dy - a.dy;
      final double length = math.sqrt(dx * dx + dy * dy);
      if (length == 0) {
        continue;
      }
      // Perpendicular offset produces a soft, non-mechanical curve.
      final Offset control =
          mid + Offset(-dy / length, dx / length) * (length * 0.10);

      final ui.Path path = ui.Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
      final ui.PathMetric metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CarePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
