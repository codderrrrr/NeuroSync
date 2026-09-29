import 'package:flutter/material.dart';

/// The hand-movement trace drawn in chapter 1: two phrases with a quiet pause
/// between them - a rise, a hesitation, a rest, a deeper swing, a soft landing.
///
/// Kept as its own geometry so the composition can be tested without painting,
/// and expressed in fractions of the box so it holds its proportions at any
/// size.
Path movementTracePath(Size size) {
  double x(double f) => size.width * f;

  double y(double f) => size.height * f;

  final Path first = Path()
    ..moveTo(x(0.02), y(0.58))
    // Rise, small hesitation.
    ..cubicTo(x(0.10), y(0.56), x(0.12), y(0.24), x(0.22), y(0.28))
    // Fall back toward the middle.
    ..cubicTo(x(0.30), y(0.31), x(0.30), y(0.52), x(0.38), y(0.55))
    // A near-flat pause: a moment of rest in the movement.
    ..cubicTo(x(0.43), y(0.57), x(0.45), y(0.62), x(0.50), y(0.61));

  final Path second = Path()
    // After the pause: a deeper swing and a soft landing.
    ..moveTo(x(0.55), y(0.52))
    ..cubicTo(x(0.63), y(0.50), x(0.62), y(0.82), x(0.72), y(0.78))
    ..cubicTo(x(0.81), y(0.75), x(0.83), y(0.36), x(0.92), y(0.40))
    ..cubicTo(x(0.96), y(0.42), x(0.97), y(0.50), x(0.99), y(0.49));

  return first..addPath(second, Offset.zero);
}
