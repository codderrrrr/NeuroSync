import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('shows the time as a quiet caption, not a large number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: const CalmProgressRing(
          progress: 0.4,
          caption: 'About 18 seconds left',
        ),
      ),
    );

    // The caption is present, and it is not the largest thing on screen.
    expect(find.text('About 18 seconds left'), findsOneWidget);
    final double captionSize = tester
        .widget<Text>(find.text('About 18 seconds left'))
        .style!
        .fontSize!;
    expect(captionSize, lessThanOrEqualTo(17));
  });

  testWidgets('draws a ring that fills with the progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(child: const CalmProgressRing(progress: 0.5)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a progress beyond the ends is drawn as a full or empty ring', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(child: const CalmProgressRing(progress: 2)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(child: const CalmProgressRing(progress: -1)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ring is announced as a progress value', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(child: const CalmProgressRing(progress: 0.25)),
    );
    await tester.pumpAndSettle();

    // A screen reader should be able to say how far along the recording is.
    expect(
      find.bySemanticsLabel('Recording progress, 25 percent'),
      findsOneWidget,
    );
  });
}
