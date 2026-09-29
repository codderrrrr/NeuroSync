import 'package:flutter/material.dart';

/// The onboarding progress control, drawn as a personal baseline.
///
/// Each chapter traced makes the line one segment more complete, so the
/// control for "where am I" is the same picture as the idea the chapters are
/// explaining: observations accumulate into a signal. It replaces a row of
/// page dots without becoming decoration - it is the progress indicator.
class BaselineSignal extends StatelessWidget {
  const BaselineSignal({
    super.key,
    required this.count,
    required this.index,
    required this.onSelect,
  });

  static const double height = 30;

  final int count;
  final int index;

  /// Called when an already-visited chapter is tapped. Forward jumps stay with
  /// Continue so the patient always reads in order.
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Chapter ${index + 1} of $count',
      child: SizedBox(
        height: height,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < count; i++) ...<Widget>[
              Expanded(
                child: _SignalSegment(
                  level: _levelFor(i),
                  current: i == index,
                  filled: i <= index,
                  onTap: (i < index && onSelect != null)
                      ? () => onSelect!(i)
                      : null,
                  lineColor: scheme.onSurfaceVariant,
                  accentColor: scheme.primary,
                ),
              ),
              if (i != count - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// 1.0 for the present chapter, less for earlier ones, 0 for the future.
  double _levelFor(int i) {
    if (i > index) {
      return 0;
    }
    return 1.0 - (index - i) * 0.26;
  }
}

class _SignalSegment extends StatelessWidget {
  const _SignalSegment({
    required this.level,
    required this.current,
    required this.filled,
    required this.lineColor,
    required this.accentColor,
    this.onTap,
  });

  final double level;
  final bool current;
  final bool filled;
  final Color lineColor;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget segment = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: level),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return CustomPaint(
          size: const Size.fromHeight(BaselineSignal.height),
          painter: _SegmentPainter(
            level: value,
            current: current,
            faint: !filled,
            lineColor: lineColor,
            accentColor: accentColor,
          ),
        );
      },
    );

    if (onTap == null) {
      return segment;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: segment,
    );
  }
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter({
    required this.level,
    required this.current,
    required this.faint,
    required this.lineColor,
    required this.accentColor,
  });

  final double level;
  final bool current;
  final bool faint;
  final Color lineColor;
  final Color accentColor;

  /// A short tremor around the centre line, expressed as fractions of the
  /// segment so it reads the same at any width.
  static const List<double> _trace = <double>[
    0.50,
    0.50,
    0.46,
    0.55,
    0.42,
    0.53,
    0.48,
    0.57,
    0.45,
    0.51,
    0.50,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double mid = size.height / 2;
    final double reach = faint ? size.width * 0.55 : size.width;

    final Path trace = Path()..moveTo(0, mid);
    final double step = reach / (_trace.length - 1);
    for (int i = 1; i < _trace.length; i++) {
      final double x = step * i;
      // Flat at the ends so adjacent segments join into one continuous line.
      final double taper = (i / (_trace.length - 1));
      final double envelope =
          (taper < 0.2 ? taper / 0.2 : (taper > 0.8 ? (1 - taper) / 0.2 : 1.0));
      trace.lineTo(x, mid + (_trace[i] - 0.5) * size.height * 0.62 * envelope);
    }

    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (faint) {
      // An unread chapter is a stub of the line: present, but not yet drawn.
      base.color = lineColor.withValues(alpha: 0.28);
      canvas.drawPath(trace, base);
      return;
    }

    base.color = Color.lerp(
        lineColor.withValues(alpha: 0.5), accentColor, level * 0.85)!;
    base.strokeWidth = current ? 1.5 : 1.2;
    canvas.drawPath(trace, base);

    if (current) {
      // The present observation: one lit point resting on the line.
      final Paint tip = Paint()
        ..color = accentColor
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(size.width, mid), 2.4, tip);
    }
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.level != level ||
      old.current != current ||
      old.faint != faint ||
      old.lineColor != lineColor ||
      old.accentColor != accentColor;
}
