import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/core/theme/intro_scale.dart';

/// Wraps a child in the media conditions [IntroScale] reads, without changing
/// the test surface: the scale is derived from the reported viewport.
Widget wrap({
  required Size size,
  required Widget child,
  double textScale = 1,
  double keyboardInset = 0,
}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: size,
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: inner!,
    ),
    // No Scaffold: a Scaffold removes the keyboard inset before building its
    // body, and the scale is meant to see it.
    home: child,
  );
}

/// Reads a value from a context built under the given conditions.
Future<T> readUnder<T>(
  WidgetTester tester, {
  required Size size,
  required T Function(BuildContext context) read,
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  late T value;
  await tester.pumpWidget(
    wrap(
      size: size,
      textScale: textScale,
      keyboardInset: keyboardInset,
      child: Builder(
        builder: (BuildContext context) {
          value = read(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return value;
}

void main() {
  testWidgets('uses the full type scale on a standard phone',
      (WidgetTester tester) async {
    final double headline = await readUnder(
      tester,
      size: const Size(360, 820),
      read: (BuildContext context) => IntroScale.of(context).headline,
    );

    expect(headline, 30);
  });

  testWidgets('compresses display text on a short viewport',
      (WidgetTester tester) async {
    final double headline = await readUnder(
      tester,
      size: const Size(360, 560),
      read: (BuildContext context) => IntroScale.of(context).headline,
    );

    // Smaller than the full size, but never below the readable floor.
    expect(headline, lessThan(30));
    expect(headline, greaterThanOrEqualTo(25));
  });

  testWidgets('keeps its scale when a keyboard opens',
      (WidgetTester tester) async {
    final double headline = await readUnder(
      tester,
      size: const Size(360, 820),
      keyboardInset: 320,
      read: (BuildContext context) => IntroScale.of(context).headline,
    );

    expect(headline, 30);
  });

  testWidgets('clamps the reading scale inside the dark experience',
      (WidgetTester tester) async {
    for (final double requested in <double>[0.5, 2.5]) {
      double? scale;
      await tester.pumpWidget(
        wrap(
          size: const Size(360, 820),
          textScale: requested,
          child: IntroTextScale(
            child: Builder(
              builder: (BuildContext context) {
                scale = MediaQuery.textScalerOf(context).scale(1);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(scale, requested < 1 ? 1.0 : 1.3);
    }
  });

  testWidgets('caps the measure of a block of copy',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        size: const Size(800, 600),
        child: Center(
          child: ReadingWidth(
            maxWidth: 300,
            child: const SizedBox(height: 8, width: 1000),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SizedBox).last).width, 300);
  });
}
