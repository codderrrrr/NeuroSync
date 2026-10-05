import 'package:flutter/material.dart';

/// Paints the marks the patient has made, on top of the guide.
///
/// The points here are the same ones the session submits, in the same order and
/// the same units. Nothing is derived, scored, smoothed or snapped to the
/// guide: this is the patient's own recording shown back to them, so someone
/// tracing a line can see what they have actually drawn and how far they got.
///
/// A finished pass is drawn in the ink colour and the pass still under the
/// finger in the active one, which is what makes "how many have I done" legible
/// while the hand is still moving.
class CanvasInkPainter extends CustomPainter {
  const CanvasInkPainter({
    required this.strokes,
    required this.completedStrokes,
    required this.pointCount,
    required this.inkColor,
    required this.activeInkColor,
  });

  /// One entry per movement of the finger, in the order they were made.
  ///
  /// The inner lists are appended to as the finger moves, so this painter reads
  /// them directly rather than taking a copy on every frame.
  final List<List<Offset>> strokes;

  /// How many entries of [strokes] the patient has lifted their finger on.
  final int completedStrokes;

  /// Total sampled points across every stroke.
  ///
  /// The stroke lists are mutated in place, so comparing them by identity would
  /// miss a new point. This is the cheap value that actually changes.
  final int pointCount;

  final Color inkColor;
  final Color activeInkColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (int index = 0; index < strokes.length; index++) {
      final List<Offset> stroke = strokes[index];
      if (stroke.isEmpty) {
        continue;
      }
      final Color color = index < completedStrokes ? inkColor : activeInkColor;
      if (stroke.length == 1) {
        // A tap with no movement: a zero-length path draws nothing, so it is
        // shown as a dot instead of silently disappearing.
        canvas.drawCircle(stroke.first, 2.5, Paint()..color = color);
        continue;
      }
      final Paint paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int point = 1; point < stroke.length; point++) {
        path.lineTo(stroke[point].dx, stroke[point].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CanvasInkPainter oldDelegate) =>
      oldDelegate.pointCount != pointCount ||
      oldDelegate.completedStrokes != completedStrokes ||
      oldDelegate.inkColor != inkColor ||
      oldDelegate.activeInkColor != activeInkColor;
}
