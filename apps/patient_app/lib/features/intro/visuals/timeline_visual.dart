import 'package:flutter/material.dart';

/// Screen 2 - Change over time: a single longitudinal timeline that extends
/// as the screen appears. Small points are observations; a quiet vertical
/// marker is medication timing. No numbers, no dashboard.
class TimelineVisual extends StatelessWidget {
  const TimelineVisual({super.key});

  /// Observation points as a fraction of the line, with relative prominence.
  static const List<double> _points = <double>[
    0.06,
    0.19,
    0.32,
    0.45,
    0.57,
    0.71,
    0.84,
    0.95
  ];

  /// Which points read as more significant, without any meaning attached.
  static const Set<int> _prominent = <int>{3, 6};

  /// Medication timing marker, as a fraction of the line.
  static const double _medicationAt = 0.64;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1700),
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double progress, Widget? child) {
        return CustomPaint(
          painter: _TimelinePainter(
            progress: progress,
            lineColor: scheme.onSurfaceVariant,
            accentColor: scheme.primary,
            points: _points,
            prominent: _prominent,
            medicationAt: _medicationAt,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.progress,
    required this.lineColor,
    required this.accentColor,
    required this.points,
    required this.prominent,
    required this.medicationAt,
  });

  final double progress;
  final Color lineColor;
  final Color accentColor;
  final List<double> points;
  final Set<int> prominent;
  final double medicationAt;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final double y = size.height * 0.5;
    final double x0 = size.width * 0.04;
    final double x1 = size.width * 0.96;
    final double span = x1 - x0;
    final double head = x0 + span * progress;

    // The timeline itself: a hairline that extends on entry.
    final Paint base = Paint()
      ..color = lineColor.withValues(alpha: 0.45)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x0, y), Offset(head, y), base);

    // A slightly warmer leading segment suggests the present moment.
    final Paint lead = Paint()
      ..color = accentColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final double leadStart = head - span * 0.06;
    if (head > leadStart) {
      canvas.drawLine(
          Offset(leadStart.clamp(x0, x1), y), Offset(head, y), lead);
    }

    // Observation points fade in as the line passes them.
    for (int i = 0; i < points.length; i++) {
      final double position = points[i];
      final double reveal = ((progress - position) * 9).clamp(0.0, 1.0);
      if (reveal <= 0) {
        continue;
      }
      final bool isProminent = prominent.contains(i);
      final double radius = isProminent ? 4.0 : 2.5;
      final Paint dot = Paint()
        ..color = isProminent
            ? accentColor.withValues(alpha: 0.9 * reveal)
            : lineColor.withValues(alpha: 0.75 * reveal)
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(x0 + span * position, y), radius, dot);
    }

    // Medication timing: one quiet vertical marker.
    final double medReveal = ((progress - medicationAt) * 6).clamp(0.0, 1.0);
    if (medReveal > 0) {
      final double mx = x0 + span * medicationAt;
      final Paint marker = Paint()
        ..color = accentColor.withValues(alpha: 0.65 * medReveal)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(mx, y - 15), Offset(mx, y + 15), marker);
      final Paint cap = Paint()
        ..color = accentColor.withValues(alpha: 0.9 * medReveal)
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(mx, y - 15), 2, cap);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
