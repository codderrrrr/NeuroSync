import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/features/account/presentation/account_screen.dart';

import '../../test_support.dart';

/// The account screen has to show which mood is chosen.
///
/// The chooser is a bar of three, and a bar that does not say which part of
/// it is chosen is a bar the patient has to think about.
void main() {
  testWidgets('the account screen shows the chosen mood', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 900);
    addTearDown(tester.view.reset);

    final PatientControllers controllers = controllersWith(
      (http.Request request) async => http.Response('[]', 200),
    );

    await tester.pumpWidget(
      patientScope(
        controllers: controllers,
        child: MaterialApp(
          theme: AppTheme.light(metrics: AppMetrics.compact),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ThemeChoiceBar), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);

    // The raised card marking the choice covers the whole of the portion it
    // is over, so the chosen mood is unmistakable.
    final Finder thumb = find.byWidgetPredicate(
      (Widget widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).boxShadow != null,
    );
    expect(thumb, findsOneWidget);

    final Rect card = tester.getRect(thumb);
    final double lightCentre = tester.getCenter(find.text('Light')).dx;
    final double darkCentre = tester.getCenter(find.text('Dark')).dx;
    expect(card.width, greaterThan((darkCentre - lightCentre) * 0.9));

    expect(tester.takeException(), isNull);
  });
}
