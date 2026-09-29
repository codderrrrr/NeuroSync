import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'movement_trace_geometry.dart';

/// Chapter 1 - Movement: a single thin line tracing a hand movement across
/// the page. It draws itself on arrival, and it can be drawn further by hand:
/// dragging along the trace extends it, releasing lets it settle back.
///
/// The trace is the thing NeuroSync records, so tracing it is the point - not
/// an effect layered on top of it.
class MovementLineVisual extends StatefulWidget {
  const MovementLineVisual({super.key, this.interactive = true});

  final bool interactive;

  @override
  State<MovementLineVisual> createState() => _MovementLineVisualState();
}

class _MovementLineVisualState extends State<MovementLineVisual>
    with TickerProviderStateMixin {
  /// Drives the entry drawing, and rests where the pointer left the trace.
  late final AnimationController _driver = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// Eases a dragged trace back to where it was resting.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _entry =
      CurvedAnimation(parent: _driver, curve: Curves.easeInOutCubic);

  double _dragTo = 0;
  bool _dragging = false;
  double _width = 320;

  @override
  void initState() {
    super.initState();
    _driver.forward();
  }

  @override
  void dispose() {
    _driver.dispose();
    _settle.dispose();
    super.dispose();
  }

  /// The length currently shown, including the drift back to rest.
  double get _progress {
    final double rest = _dragging ? _dragTo : _entry.value;
    return (rest + _settle.value * (_dragTo - _entry.value)).clamp(0.0, 1.0);
  }

  void _beginDrag(double width, Offset local) {
    _settle.stop();
    setState(() {
      // A drag starts from the pointer, never from wherever a drift had got to.
      _settle.value = 0;
      _width = width;
      _dragging = true;
      _dragTo = _progressAt(local);
    });
  }

  void _moveDrag(double width, Offset local) {
    setState(() {
      _width = width;
      _dragTo = _progressAt(local);
    });
  }

  void _endDrag() {
    if (!_dragging) {
      return;
    }
    setState(() => _dragging = false);
    _settle.value = 1;
    _settle.animateBack(
      0,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
    );
  }

  /// The pointer's position along the trace, as a fraction of its length.
  double _progressAt(Offset local) =>
      (_width <= 0) ? _entry.value : (local.dx / _width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
        final Widget painted = AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_driver, _settle]),
          builder: (BuildContext context, Widget? child) => CustomPaint(
            painter: _MovementLinePainter(
              progress: _progress,
              lineColor: scheme.primary,
              dimColor: scheme.onSurfaceVariant,
              showStylus: _dragging || _settle.isAnimating,
            ),
            child: const SizedBox.expand(),
          ),
        );

        if (!widget.interactive) {
          return painted;
        }
        // Taps and long-press drags are used deliberately: a plain horizontal
        // drag belongs to the chapter swipe, so the trace never steals it.
        // Press the line and it comes to your finger; hold and move to draw.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => _beginDrag(width, d.localPosition),
          onTapUp: (TapUpDetails _) => _endDrag(),
          onTapCancel: _endDrag,
          onLongPressStart: (LongPressStartDetails d) =>
              _beginDrag(width, d.localPosition),
          onLongPressMoveUpdate: (LongPressMoveUpdateDetails d) =>
              _moveDrag(width, d.localPosition),
          onLongPressEnd: (LongPressEndDetails _) => _endDrag(),
          child: painted,
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
    required this.showStylus,
  });

  final double progress;
  final Color lineColor;
  final Color dimColor;
  final bool showStylus;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final Path full = movementTracePath(size);
    final List<ui.PathMetric> metrics = full.computeMetrics().toList();
    final double total = metrics.fold<double>(
        0, (double sum, ui.PathMetric m) => sum + m.length);
    double travelled = progress * total;

    // A faint ghost of the whole trace keeps the composition grounded.
    final Paint ghost = Paint()
      ..color = dimColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (final ui.PathMetric metric in metrics) {
      canvas.drawPath(metric.extractPath(0, metric.length), ghost);
    }

    final Paint stroke = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    Offset tip = Offset(size.width * 0.02, size.height * 0.58);
    for (final ui.PathMetric metric in metrics) {
      if (travelled <= 0) {
        break;
      }
      final double take = travelled.clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(0, take), stroke);
      tip = metric.getTangentForOffset(take)?.position ?? tip;
      travelled -= take;
    }

    // The pen, lit only while the trace is being moved.
    if (showStylus) {
      final Paint halo = Paint()
        ..shader = ui.Gradient.radial(
          tip,
          16,
          <Color>[
            lineColor.withValues(alpha: 0.22),
            lineColor.withValues(alpha: 0.0),
          ],
        );
      canvas.drawCircle(tip, 16, halo);
      final Paint point = Paint()
        ..color = lineColor
        ..isAntiAlias = true;
      canvas.drawCircle(tip, 3, point);
    }
  }

  @override
  bool shouldRepaint(_MovementLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.showStylus != showStylus;
}
