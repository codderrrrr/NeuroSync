import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A quiet loading mark.
///
/// The stock spinner is a hard-edged arc that spins as fast as it can, which
/// draws the eye to a thing the patient is waiting on and away from the thing
/// they are doing. This is three dots that breathe, so the wait is present
/// without being loud.
class CalmLoader extends StatefulWidget {
  const CalmLoader({super.key, this.size = 22, this.color});

  /// How wide the mark is.
  final double size;

  /// The colour of the dots. Left unset, the quiet label colour is used.
  final Color? color;

  @override
  State<CalmLoader> createState() => _CalmLoaderState();
}

class _CalmLoaderState extends State<CalmLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = widget.color ?? colors.secondaryLabel;

    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              painter: _DotsPainter(
                progress: _controller.value,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const int dotCount = 3;
    final double radius = size.width * 0.09;
    final double gap = size.width / (dotCount + 1);
    final Paint paint = Paint()..color = color;

    for (int index = 0; index < dotCount; index++) {
      // Each dot is a little behind the one before it, so the row reads as a
      // wave rather than three dots blinking at once.
      final double phase = (progress - index * 0.18) % 1.0;
      final double swell = math.sin(phase * math.pi).abs();
      final double dotRadius = radius * (0.55 + 0.45 * swell);
      final double dx = gap * (index + 1);
      final double dy = size.height / 2;
      paint.color = color.withValues(alpha: 0.35 + 0.65 * swell);
      canvas.drawCircle(Offset(dx, dy), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
