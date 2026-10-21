import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/core/widgets/stat_strip.dart';

/// The stat strip has to hold its words on a phone.
///
/// The numbers and captions are short by design, and this is what holds them
/// to it: a word that will not fit in its column is a word that gets cut off,
/// and a caption the patient cannot read is worse than no caption.
void main() {
  Widget wrap({required Widget child, double width = 360}) {
    return MaterialApp(
      theme: AppTheme.light(metrics: AppMetrics.compact),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }

  StatStrip strip() => StatStrip(
        stats: const <StatEntry>[
          StatEntry(
            value: 'Done',
            caption: "today's test",
            icon: Icons.check_circle_outline,
            emphasis: true,
          ),
          StatEntry(
            value: '2',
            caption: 'tests today',
            icon: Icons.timelapse_outlined,
          ),
          StatEntry(
            value: '3',
            caption: 'medicines',
            icon: Icons.medication_outlined,
          ),
        ],
      );

  for (final double width in <double>[320, 360, 393, 412]) {
    testWidgets('the strip holds together at ${width.toInt()}px', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(child: strip()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Every word is shown in full. A word that does not fit is not wrapped
      // and cut short: it is silently replaced with an ellipsis, which the
      // patient reads as a mistake.
      for (final String word in <String>[
        'Done',
        "today's test",
        'tests today',
        'medicines',
      ]) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(word),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$word" does not fit its column',
        );
      }
    });
  }

  testWidgets('the three numbers sit on one line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(child: strip()));
    await tester.pumpAndSettle();

    // The tops line up, not the middles: the emphasised number is a little
    // larger, so a row read from the middle would be a row read off by a
    // pixel.
    final double first = tester.getTopLeft(find.text('Done')).dy;
    final double second = tester.getTopLeft(find.text('2')).dy;
    final double third = tester.getTopLeft(find.text('3')).dy;
    expect(second, moreOrLessEquals(first, epsilon: 0.5));
    expect(third, moreOrLessEquals(first, epsilon: 0.5));
  });

  testWidgets('the marks are aligned with the numbers under them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(child: strip()));
    await tester.pumpAndSettle();

    // Each mark sits directly above its own number, not beside another one.
    final double mark =
        tester.getCenter(find.byIcon(Icons.timelapse_outlined)).dx;
    final double number = tester.getCenter(find.text('2')).dx;
    expect(mark, moreOrLessEquals(number, epsilon: 1));
  });
}
