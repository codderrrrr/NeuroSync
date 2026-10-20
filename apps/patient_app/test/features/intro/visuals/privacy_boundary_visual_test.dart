import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/visuals/privacy_boundary_visual.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap({double width = 320, double height = 420}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: const PrivacyBoundaryVisual(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('says nothing has been shared until the patient shares it',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Tap to see what is shared.'), findsOneWidget);
    expect(find.textContaining('shared with your care team'), findsNothing);
  });

  testWidgets('opening the route states exactly what leaves',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PrivacyBoundaryVisual));
    await tester.pumpAndSettle();

    expect(find.text('Tap to see what is shared.'), findsNothing);
    expect(
      find.text(
        'Assessment result and medication timing, shared with your care team.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('closes again when tapped a second time',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PrivacyBoundaryVisual));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrivacyBoundaryVisual));
    await tester.pumpAndSettle();

    expect(find.text('Tap to see what is shared.'), findsOneWidget);
  });

  testWidgets('fits the smallest band onboarding gives it',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(width: 300, height: 140));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CARE TEAM'), findsOneWidget);
  });
}
