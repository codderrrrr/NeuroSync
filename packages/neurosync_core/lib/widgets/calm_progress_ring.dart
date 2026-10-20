import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A quiet ring that fills as a recording goes on.
///
/// A countdown turns the recording into a test: the number gets larger, the
/// patient starts watching it rather than the task, and the last seconds
/// arrive as pressure. This shows the same information as a growing arc, which
/// the eye reads without having to decode a digit that is changing.
///
/// The remaining time is still there, but as a quiet caption under the ring
/// rather than the largest thing on the screen.
class CalmProgressRing extends StatelessWidget {
  const CalmProgressRing({
    super.key,
    required this.progress,
    this.size = 116,
    this.strokeWidth = 10,
    this.caption,
  });

  /// How far through the recording is, from 0 to 1.
  final double progress;

  /// The diameter of the ring.
  final double size;

  /// How thick the arc is.
  final double strokeWidth;

  /// A short line under the ring, such as the time remaining.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final double value = progress.clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          label: 'Recording progress, ${(value * 100).round()} percent',
          child: SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: value, end: value),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              builder: (BuildContext context, double shown, Widget? child) {
                return CustomPaint(
                  painter: _RingPainter(
                    progress: shown,
                    track: colors.surfaceSunken,
                    fill: colors.primary,
                  ),
                );
              },
            ),
          ),
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            caption!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: colors.secondaryLabel,
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = (size.shortestSide / 2) - 6;
    final Rect bounds = Rect.fromCircle(center: centre, radius: radius);

    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(centre, radius, trackPaint);

    if (progress <= 0) {
      return;
    }

    final Paint fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    // A quarter turn puts the start of the arc at the top, where a clock
    // would start, rather than at three o'clock.
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.fill != fill;
}
