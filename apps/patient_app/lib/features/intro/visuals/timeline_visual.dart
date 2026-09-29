import 'package:flutter/material.dart';

/// Chapter 2 - Change over time: one longitudinal line running down the page,
/// with observations resting on it and a single quiet marker for medication
/// timing. No numbers, no axes, no dashboard.
///
/// [progress] is how far the patient has come through the chapters, so the
/// line on the page is different on every chapter: a visual about signal
/// accumulating over time accumulates as the story is read.
class TimelineVisual extends StatelessWidget {
  const TimelineVisual({super.key, this.progress = 1});

  /// Observation points, as a fraction of the line from top to bottom.
  static const List<double> _points = <double>[
    0.06,
    0.19,
    0.32,
    0.45,
    0.57,
    0.71,
    0.84,
    0.95,
  ];

  /// Points that read as more prominent, without any meaning attached.
  static const Set<int> _prominent = <int>{3, 6};

  /// Medication timing marker, as a fraction of the line.
  static const double _medicationAt = 0.64;

  final double progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // When progress changes the builder animates from where the line already
    // was, so the timeline grows rather than replaying from nothing.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) =>
          CustomPaint(
        painter: _TimelinePainter(
          progress: value,
          lineColor: scheme.onSurfaceVariant,
          accentColor: scheme.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.progress,
    required this.lineColor,
    required this.accentColor,
  });

  final double progress;
  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final double x = size.width / 2;
    final double top = size.height * 0.05;
    final double bottom = size.height * 0.95;
    final double span = bottom - top;
    final double head = top + span * progress;

    // The timeline itself: a hairline that extends as observations arrive.
    final Paint base = Paint()
      ..color = lineColor.withValues(alpha: 0.45)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, top), Offset(x, head), base);

    // A slightly stronger leading segment marks the present moment.
    final double leadStart = (head - span * 0.06).clamp(top, bottom);
    if (head > leadStart) {
      final Paint lead = Paint()
        ..color = accentColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, leadStart), Offset(x, head), lead);
    }

    // Observations settle onto the line as it passes them.
    for (int i = 0; i < TimelineVisual._points.length; i++) {
      final double position = TimelineVisual._points[i];
      final double reveal = ((progress - position) * 9).clamp(0.0, 1.0);
      if (reveal <= 0) {
        continue;
      }
      final double y = top + span * position;
      final bool prominent = TimelineVisual._prominent.contains(i);
      if (prominent) {
        // A quiet ring rather than a bigger dot: emphasis without hierarchy.
        final Paint ring = Paint()
          ..color = lineColor.withValues(alpha: 0.28 * reveal)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..isAntiAlias = true;
        canvas.drawCircle(Offset(x, y), 6, ring);
      }
      final Paint dot = Paint()
        ..color = (prominent ? accentColor : lineColor)
            .withValues(alpha: (prominent ? 0.9 : 0.75) * reveal)
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(x, y), prominent ? 3.2 : 2.4, dot);
    }

    // Medication timing: one quiet cross-tick, revealed only once the line has
    // reached it - context arrives with the data it belongs to.
    final double medReveal =
        ((progress - TimelineVisual._medicationAt) * 6).clamp(0.0, 1.0);
    if (medReveal > 0) {
      final double y = top + span * TimelineVisual._medicationAt;
      final Paint marker = Paint()
        ..color = accentColor.withValues(alpha: 0.65 * medReveal)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x - 14, y), Offset(x + 14, y), marker);
      final Paint cap = Paint()
        ..color = accentColor.withValues(alpha: 0.9 * medReveal)
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(x + 14, y), 2, cap);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
