import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/features/intro/onboarding_screen.dart';
import 'package:neurosync_patient/features/intro/visuals/movement_line_visual.dart';

Future<void> pumpOnboarding(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: OnboardingScreen(onFinished: () {}),
    ),
  );
  await tester.pumpAndSettle();
}

Size viewport(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

void main() {
  testWidgets('balances the page on a 360x820 phone',
      (WidgetTester tester) async {
    await pumpOnboarding(tester, size: const Size(360, 820));

    expect(tester.takeException(), isNull);

    final Rect visual = tester.getRect(find.byType(MovementLineVisual));
    final Rect headline =
        tester.getRect(find.text('Understand your movement.'));
    final Rect action = tester.getRect(find.text('Continue'));

    // Visual, copy, action: in order, all on screen, none clipped.
    expect(visual.top, greaterThan(0));
    expect(visual.bottom, lessThan(headline.top));
    expect(headline.bottom, lessThan(action.top));
    expect(action.bottom, lessThanOrEqualTo(820));

    // The visual is a band, not a token, and the space above it is a leading,
    // not a void.
    expect(visual.height, greaterThan(140));
    expect(visual.top, lessThan(820 * 0.2));
  });

  testWidgets('lays out two columns in landscape', (WidgetTester tester) async {
    await pumpOnboarding(tester, size: const Size(820, 360));

    expect(tester.takeException(), isNull);

    final Rect visual = tester.getRect(find.byType(MovementLineVisual));
    final Rect headline =
        tester.getRect(find.text('Understand your movement.'));
    final Rect action = tester.getRect(find.text('Continue'));

    // Side by side rather than stacked, and the copy keeps its own measure.
    expect(headline.left, greaterThan(visual.right));
    expect(headline.width, lessThan(420));
    expect(action.bottom, lessThanOrEqualTo(360));
    expect(headline.top, greaterThanOrEqualTo(0));
    expect(headline.bottom, lessThanOrEqualTo(360));
  });

  testWidgets('holds together at the largest system text scale',
      (WidgetTester tester) async {
    await pumpOnboarding(tester, size: const Size(360, 820), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Understand your movement.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(
        tester.getRect(find.text('Continue')).bottom, lessThanOrEqualTo(820));
  });

  testWidgets('fits a small phone', (WidgetTester tester) async {
    await pumpOnboarding(tester, size: const Size(320, 568));

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
    expect(
        tester.getRect(find.text('Continue')).bottom, lessThanOrEqualTo(568));
    expect(find.byType(MovementLineVisual), findsOneWidget);
  });

  testWidgets('keeps the action reachable in a very short viewport',
      (WidgetTester tester) async {
    // Nothing can be composed at this height, so the page scrolls instead of
    // clipping the copy or hiding the action.
    await pumpOnboarding(tester, size: const Size(360, 380));

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.getRect(find.text('Continue')).bottom,
        lessThanOrEqualTo(viewport(tester).height));
  });
}
