import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen 4 - Privacy: an illuminated point (the patient's data) resting
/// inside a quiet boundary, with faint labels outside it. Controlled access,
/// without the language or imagery of a security product.
class PrivacyBoundaryVisual extends StatelessWidget {
  const PrivacyBoundaryVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1700),
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double t, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double side =
                math.min(constraints.maxWidth, constraints.maxHeight);
            final double boundaryReveal = (t / 0.6).clamp(0.0, 1.0);
            final double pointReveal = ((t - 0.4) / 0.5).clamp(0.0, 1.0);
            return Center(
              child: SizedBox(
                width: side,
                height: side,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BoundaryPainter(
                          boundaryProgress: boundaryReveal,
                          pointOpacity: pointReveal,
                          lineColor: scheme.onSurfaceVariant,
                          accentColor: scheme.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 10,
                      child: _FaintLabel(text: 'PATIENT', opacity: pointReveal),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 10,
                      child:
                          _FaintLabel(text: 'CARE TEAM', opacity: pointReveal),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FaintLabel extends StatelessWidget {
  const _FaintLabel({required this.text, required this.opacity});

  final String text;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity * 0.6,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BoundaryPainter extends CustomPainter {
  const _BoundaryPainter({
    required this.boundaryProgress,
    required this.pointOpacity,
    required this.lineColor,
    required this.accentColor,
  });

  final double boundaryProgress;
  final double pointOpacity;
  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) * 0.30;

    // The boundary: one thin, quietly drawn circle.
    if (boundaryProgress > 0) {
      final ui.Path circle = ui.Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      final ui.PathMetric metric = circle.computeMetrics().first;
      final Paint boundary = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true;
      canvas.drawPath(
        metric.extractPath(0, metric.length * boundaryProgress),
        boundary,
      );
    }

    // The illuminated point: restrained, never neon.
    if (pointOpacity > 0) {
      final Paint halo = Paint()
        ..shader = ui.Gradient.radial(
          center,
          22,
          <Color>[
            accentColor.withValues(alpha: 0.28 * pointOpacity),
            accentColor.withValues(alpha: 0.0),
          ],
        );
      canvas.drawCircle(center, 22, halo);

      final Paint point = Paint()
        ..color = accentColor.withValues(alpha: pointOpacity)
        ..isAntiAlias = true;
      canvas.drawCircle(center, 4, point);
    }
  }

  @override
  bool shouldRepaint(_BoundaryPainter oldDelegate) =>
      oldDelegate.boundaryProgress != boundaryProgress ||
      oldDelegate.pointOpacity != pointOpacity;
}
