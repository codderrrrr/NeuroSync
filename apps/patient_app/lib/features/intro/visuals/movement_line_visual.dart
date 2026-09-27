import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen 1 - Movement: a single thin line tracing a human hand movement
/// across the screen. It draws itself on entry, with a deliberate pause and
/// small imperfections. It is not a chart.
class MovementLineVisual extends StatelessWidget {
  const MovementLineVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double progress, Widget? child) {
        return CustomPaint(
          painter: _MovementLinePainter(
            progress: progress,
            lineColor: scheme.primary,
            dimColor: scheme.onSurfaceVariant,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _MovementLinePainter extends CustomPainter {
  const _MovementLinePainter({
    required this.progress,
    required this.lineColor,
    required this.dimColor,
  });

  final double progress;
  final Color lineColor;
  final Color dimColor;

  Path _buildPath(Size size) {
    final Path path = Path()
      ..moveTo(size.width * 0.02, size.height * 0.58)
      // First phrase: rise, small hesitation, fall.
      ..cubicTo(
        size.width * 0.10,
        size.height * 0.56,
        size.width * 0.12,
        size.height * 0.24,
        size.width * 0.22,
        size.height * 0.28,
      )
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.31,
        size.width * 0.30,
        size.height * 0.52,
        size.width * 0.38,
        size.height * 0.55,
      )
      // A near-flat pause - a moment of rest in the movement.
      ..cubicTo(
        size.width * 0.43,
        size.height * 0.57,
        size.width * 0.45,
        size.height * 0.62,
        size.width * 0.50,
        size.height * 0.61,
      );

    final Path second = Path()
      // Second phrase after the pause: a deeper swing and a soft landing.
      ..moveTo(size.width * 0.55, size.height * 0.52)
      ..cubicTo(
        size.width * 0.63,
        size.height * 0.50,
        size.width * 0.62,
        size.height * 0.82,
        size.width * 0.72,
        size.height * 0.78,
      )
      ..cubicTo(
        size.width * 0.81,
        size.height * 0.75,
        size.width * 0.83,
        size.height * 0.36,
        size.width * 0.92,
        size.height * 0.40,
      )
      ..cubicTo(
        size.width * 0.96,
        size.height * 0.42,
        size.width * 0.97,
        size.height * 0.50,
        size.width * 0.99,
        size.height * 0.49,
      );

    return path..addPath(second, Offset.zero);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final Path full = _buildPath(size);
    final List<ui.PathMetric> metrics = full.computeMetrics().toList();
    final double total = metrics.fold<double>(
        0, (double sum, ui.PathMetric m) => sum + m.length);
    double travelled = progress * total;

    final Paint paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // A faint ghost of the full path keeps the composition grounded.
    final Paint ghost = Paint()
      ..color = dimColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (final ui.PathMetric metric in metrics) {
      canvas.drawPath(metric.extractPath(0, metric.length), ghost);
    }

    for (final ui.PathMetric metric in metrics) {
      if (travelled <= 0) {
        break;
      }
      final double take = travelled.clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(0, take), paint);
      travelled -= take;
    }
  }

  @override
  bool shouldRepaint(_MovementLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
