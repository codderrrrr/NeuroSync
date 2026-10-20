import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/assessment.dart';
import '../models/monitoring_plan.dart';

/// The shape a tracing test asks the patient to draw.
///
/// The size and turn count come from the doctor's settings, so the patient
/// draws exactly what they were assigned rather than a fixed figure the app
/// decided on. The shape is a guide only: the app never scores how closely the
/// finger stayed on it.
enum CanvasTargetShape { spiral, line, handwriting }

class CanvasTarget {
  const CanvasTarget._(this.shape, this.turns, this.sizeFraction, this.phrase);

  /// The target for one catalog assessment, using parameter keys rather than
  /// hardcoded slugs so the guide adapts to whatever the catalog declares.
  factory CanvasTarget.forAssessment({
    required Assessment assessment,
    required MonitoringPlanItem item,
  }) {
    // Determine shape from execution type or slug convention
    final bool isSpiral = assessment.slug == 'spiral_drawing';
    final bool isHandwriting = assessment.slug == 'handwriting';

    // Look up parameters by conventional keys
    int turns = 1;
    int sizePercent = 70;
    int lineLengthPercent = 70;
    String phrase = 'NeuroSync';

    for (final setting in assessment.parameters) {
      final value = item.parameters[setting.key] ?? setting.defaultValue;
      switch (setting.key) {
        case 'turns':
          turns = (value as num).toInt();
        case 'size_percent':
          sizePercent = (value as num).toInt();
        case 'line_length_percent':
          lineLengthPercent = (value as num).toInt();
        case 'phrase':
          phrase = value as String;
        case 'repetitions':
          // Handled by strokes_parameter in catalog
          break;
      }
    }

    if (isSpiral) {
      return CanvasTarget._(
        CanvasTargetShape.spiral,
        math.max(1, turns),
        (sizePercent.clamp(40, 100)) / 100,
        '',
      );
    } else if (isHandwriting) {
      return CanvasTarget._(
        CanvasTargetShape.handwriting,
        0,
        0.7,
        phrase.trim().isEmpty ? 'NeuroSync' : phrase.trim(),
      );
    } else {
      // line_tracing or unknown canvas task
      return CanvasTarget._(
        CanvasTargetShape.line,
        0,
        (lineLengthPercent.clamp(30, 100)) / 100,
        '',
      );
    }
  }

  final CanvasTargetShape shape;

  /// Full turns of the spiral; unused by the other shapes.
  final int turns;

  /// How much of the shorter side the shape occupies, as a fraction.
  final double sizeFraction;

  /// The words to write, for the handwriting shape.
  final String phrase;
}

/// Paints the guide and, while recording, nothing else.
///
/// Deliberately not drawing the patient's own line back at them: a live
/// rendering that differs from the one the backend stores would be a second,
/// slightly different account of the same recording.
class CanvasTargetPainter extends CustomPainter {
  const CanvasTargetPainter({
    required this.target,
    required this.strokeColor,
    required this.guideColor,
  });

  final CanvasTarget target;
  final Color strokeColor;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint guide = Paint()
      ..color = guideColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Paint line = Paint()
      ..color = strokeColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    switch (target.shape) {
      case CanvasTargetShape.spiral:
        _paintSpiral(canvas, size, line);
      case CanvasTargetShape.line:
        _paintLine(canvas, size, guide, line);
      case CanvasTargetShape.handwriting:
        _paintHandwriting(canvas, size, guide);
    }
  }

  double get _shortestSide => 1;

  void _paintSpiral(Canvas canvas, Size size, Paint paint) {
    final Offset centre = size.center(Offset.zero);
    final double radius =
        size.shortestSide / 2 * target.sizeFraction * _shortestSide;
    const int samplesPerTurn = 48;
    final Path path = Path();
    final int total = math.max(1, target.turns) * samplesPerTurn;
    for (int i = 0; i <= total; i++) {
      final double t = i / total;
      final double angle = t * target.turns * 2 * math.pi;
      final double r = radius * t;
      final Offset point =
          centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
    canvas.drawCircle(centre, 4, Paint()..color = paint.color);
  }

  void _paintLine(Canvas canvas, Size size, Paint guide, Paint line) {
    final double width = size.width * target.sizeFraction;
    final double left = (size.width - width) / 2;
    final double y = size.height / 2;
    canvas.drawLine(Offset(left, y), Offset(left + width, y), guide);
    for (final double x in <double>[left, left + width]) {
      canvas.drawCircle(Offset(x, y), 9, Paint()..color = line.color);
    }
  }

  void _paintHandwriting(Canvas canvas, Size size, Paint guide) {
    final String phrase =
        target.phrase.trim().isEmpty ? 'NeuroSync' : target.phrase.trim();
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: phrase,
        style: TextStyle(
          color: guide.color.withValues(alpha: 0.5),
          fontSize: math.max(20.0, size.width / (phrase.length * 0.55)),
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * target.sizeFraction);
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(CanvasTargetPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.guideColor != guideColor;
}
