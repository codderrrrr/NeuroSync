import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Chapter 3 - Connected care: three typographic nodes joined by extremely
/// thin curves. They appear apart and settle gently into alignment - editorial
/// information design, not a network diagram. The alignment is the sentence:
/// separate people, brought into agreement about one patient.
class ConnectedCareVisual extends StatelessWidget {
  const ConnectedCareVisual({super.key});

  /// Where each node starts, as a fraction of the canvas: scattered.
  static const List<Offset> _scattered = <Offset>[
    Offset(0.26, 0.22),
    Offset(0.76, 0.50),
    Offset(0.28, 0.84),
  ];

  /// Angles, in radians, of the equally spaced points the nodes settle into.
  static const List<double> _alignedAngles = <double>[
    -math.pi / 2,
    math.pi / 6,
    5 * math.pi / 6,
  ];

  static const List<String> _labels = <String>[
    'PATIENT',
    'CAREGIVER',
    'CLINICIAN',
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double t, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size canvas =
                Size(constraints.maxWidth, constraints.maxHeight);
            // Nodes appear apart, then take their time coming into line.
            final double align = ((t - 0.45) / 0.5).clamp(0.0, 1.0);
            final List<Offset> anchors = _anchorPositions(canvas, align);
            return CustomPaint(
              painter: _CarePainter(
                progress: ((t - 0.25) / 0.6).clamp(0.0, 1.0),
                lineColor: scheme.onSurfaceVariant,
                points: anchors,
              ),
              child: Stack(
                children: <Widget>[
                  for (int i = 0; i < anchors.length; i++)
                    _Node(
                      label: _labels[i],
                      position: anchors[i],
                      canvasWidth: canvas.width,
                      appear: ((t - i * 0.15) / 0.55).clamp(0.0, 1.0),
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

  /// Node centres in pixels, interpolated between scattered and aligned.
  static List<Offset> _anchorPositions(Size canvas, double align) {
    final Offset center = Offset(canvas.width / 2, canvas.height / 2);
    // An ellipse rather than a circle, so the three nodes fill a tall band
    // instead of clustering in the middle of it.
    final Offset radii = Offset(canvas.width * 0.30, canvas.height * 0.33);
    return <Offset>[
      for (int i = 0; i < _scattered.length; i++)
        Offset.lerp(
          Offset(
            _scattered[i].dx * canvas.width,
            _scattered[i].dy * canvas.height,
          ),
          center +
              Offset(
                math.cos(_alignedAngles[i]) * radii.dx,
                math.sin(_alignedAngles[i]) * radii.dy,
              ),
          Curves.easeOutCubic.transform(align),
        )!,
    ];
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.label,
    required this.position,
    required this.canvasWidth,
    required this.appear,
    required this.color,
  });

  final String label;
  final Offset position;
  final double canvasWidth;
  final double appear;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Labels are centred on their node but kept inside the canvas, so a
    // narrow landscape column cannot push a word off the edge.
    final double width = canvasWidth < 140 ? canvasWidth : 140.0;
    final double left =
        (position.dx - width / 2).clamp(0.0, canvasWidth - width);
    return Positioned(
      left: left,
      top: position.dy - 11 + (1 - appear) * 10,
      width: width,
      height: 22,
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
    required this.points,
  });

  final double progress;
  final Color lineColor;
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress <= 0) {
      return;
    }

    final Paint paint = Paint()
      ..color = lineColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

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
      // A small perpendicular offset keeps the connector from reading as a
      // straight technical line, and shortens it clear of the labels.
      final Offset control =
          mid + Offset(-dy / length, dx / length) * (length * 0.10);
      final ui.Path path = ui.Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
      final ui.PathMetric metric = path.computeMetrics().first;
      // Trim both ends so the line joins the space between nodes, not the
      // middle of a word.
      final double start = (metric.length * 0.14).clamp(0.0, metric.length);
      final double end = (metric.length * 0.86).clamp(start, metric.length);
      canvas.drawPath(
        metric.extractPath(start, start + (end - start) * progress),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CarePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.points != points;
}
