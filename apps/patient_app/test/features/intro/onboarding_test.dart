import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/onboarding_screen.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrapOnboarding({required VoidCallback onFinished}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: OnboardingScreen(onFinished: onFinished),
  );
}

void main() {
  testWidgets('Continue advances through every chapter to Get Started',
      (WidgetTester tester) async {
    int finished = 0;
    await tester.pumpWidget(wrapOnboarding(onFinished: () => finished++));
    await tester.pumpAndSettle();

    expect(find.text('Understand your movement.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('See what changes.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Care that stays connected.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your health information stays yours.'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(finished, 0);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('swiping moves to the next chapter', (WidgetTester tester) async {
    int finished = 0;
    await tester.pumpWidget(wrapOnboarding(onFinished: () => finished++));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('See what changes.'), findsOneWidget);
    expect(finished, 0);
  });

  testWidgets('Skip finishes immediately', (WidgetTester tester) async {
    int finished = 0;
    await tester.pumpWidget(wrapOnboarding(onFinished: () => finished++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(finished, 1);
  });
}
