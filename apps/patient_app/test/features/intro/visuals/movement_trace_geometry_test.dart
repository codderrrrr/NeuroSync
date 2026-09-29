import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/visuals/movement_trace_geometry.dart';

const List<Size> _boxes = <Size>[
  Size(320, 220),
  Size(300, 400),
  Size(600, 120),
  Size(96, 54),
];

void main() {
  test('stays inside its box at every size it is asked to fill', () {
    for (final Size size in _boxes) {
      final Path path = movementTracePath(size);
      final Iterable<PathMetric> metrics = path.computeMetrics();
      expect(metrics.length, 2, reason: 'two phrases');

      for (final PathMetric metric in metrics) {
        for (int step = 0; step <= 40; step++) {
          final Offset? point =
              metric.getTangentForOffset(metric.length * step / 40)?.position;
          expect(point, isNotNull);
          expect(point!.dx, inInclusiveRange(-1, size.width + 1));
          expect(point.dy, inInclusiveRange(-1, size.height + 1));
        }
      }
    }
  });

  test('is drawn left to right, with a rest between the phrases', () {
    const Size size = Size(320, 220);
    final List<PathMetric> metrics =
        movementTracePath(size).computeMetrics().toList();

    for (final PathMetric metric in metrics) {
      double previous = -1;
      for (int step = 0; step <= 60; step++) {
        final Offset point =
            metric.getTangentForOffset(metric.length * step / 60)!.position;
        expect(point.dx, greaterThanOrEqualTo(previous - 0.01));
        previous = point.dx;
      }
      expect(previous, greaterThan(size.width * 0.4));
    }

    // The gap between the two phrases is where the trace rests.
    final double endOfFirst =
        metrics.first.getTangentForOffset(metrics.first.length)!.position.dx;
    final double startOfSecond =
        metrics.last.getTangentForOffset(0)!.position.dx;
    expect(startOfSecond, greaterThan(endOfFirst));
  });

  test('scales with its box rather than its position', () {
    final Offset small = movementTracePath(const Size(100, 100))
        .computeMetrics()
        .first
        .getTangentForOffset(0)!
        .position;
    final Offset large = movementTracePath(const Size(200, 200))
        .computeMetrics()
        .first
        .getTangentForOffset(0)!
        .position;

    expect(large.dx, closeTo(small.dx * 2, 0.01));
    expect(large.dy, closeTo(small.dy * 2, 0.01));
  });
}
