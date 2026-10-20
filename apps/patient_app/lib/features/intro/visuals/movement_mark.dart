import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// Painter for the NeuroSync mark: a single continuous line that rises,
/// settles and passes through a small loop - movement, continuity and
/// connection expressed without literal imagery.
class MovementMarkPainter extends CustomPainter {
  MovementMarkPainter({required this.progress, required this.color});

  /// 0 to 1 draw progress of the line.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress <= 0) {
      return;
    }

    final Path path = Path()
      ..moveTo(size.width * 0.04, size.height * 0.62)
      // First swell: a calm rise with a soft plateau.
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.62,
        size.width * 0.20,
        size.height * 0.26,
        size.width * 0.36,
        size.height * 0.30,
      )
      // Settle down into the second swell.
      ..cubicTo(
        size.width * 0.50,
        size.height * 0.34,
        size.width * 0.48,
        size.height * 0.74,
        size.width * 0.62,
        size.height * 0.70,
      )
      // A small continuous loop - the sync gesture.
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.67,
        size.width * 0.76,
        size.height * 0.50,
        size.width * 0.66,
        size.height * 0.48,
      )
      ..cubicTo(
        size.width * 0.56,
        size.height * 0.46,
        size.width * 0.58,
        size.height * 0.68,
        size.width * 0.74,
        size.height * 0.64,
      )
      // Exit right with a gentle lift.
      ..cubicTo(
        size.width * 0.86,
        size.height * 0.61,
        size.width * 0.90,
        size.height * 0.44,
        size.width * 0.97,
        size.height * 0.40,
      );

    final ui.PathMetric metric = path.computeMetrics().first;
    final Path drawn =
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.055).clamp(1.6, 3.2)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(MovementMarkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// The NeuroSync mark, drawn to a fixed aspect box.
class MovementMark extends StatelessWidget {
  const MovementMark({
    super.key,
    required this.progress,
    this.color,
    this.size = const Size(108, 60),
  });

  final double progress;

  /// The colour of the mark. Left unset, it takes the theme's primary.
  final Color? color;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: MovementMarkPainter(
        progress: progress,
        color: color ?? AppColors.of(context).primary,
      ),
    );
  }
}
