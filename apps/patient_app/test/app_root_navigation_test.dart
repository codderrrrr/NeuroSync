import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/app.dart';
import 'package:neurosync_patient/core/widgets/floating_tab_bar.dart';

import 'test_support.dart';

/// Pumps the real [NeuroSyncApp] with a stored session, so the root decides
/// what a signed-in patient actually sees.
Widget signedInApp() {
  final PatientControllers controllers = controllersWith(
    (http.Request request) async {
      if (request.url.path == '/auth/me') {
        return json(patientJson());
      }
      // Every list endpoint answers empty; the root only needs them to settle.
      return http.Response('[]', 200);
    },
    storedToken: 'stored-token',
  );

  return NeuroSyncApp(
    authController: controllers.auth,
    doctorLinkController: controllers.doctorLinks,
    checkInController: controllers.checkIns,
    monitoringController: controllers.monitoring,
    medicationController: controllers.medications,
    themeController: ThemeController(),
  );
}

/// Pumps the app past the intro flow's splash minimum, which is a real timer
/// rather than an animation, so `pumpAndSettle` alone leaves it pending.
Future<void> pumpSignedInApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1600);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(signedInApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2000));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a signed-in patient lands in the shell, not a bare home screen',
      (WidgetTester tester) async {
    // Regression: the root rendered HomeScreen directly, so MainShell never
    // appeared and the tests, medicine and doctor-linking tabs were unreachable.
    await pumpSignedInApp(tester);

    expect(find.byType(FloatingTabBar), findsOneWidget);
    // Every destination keeps its label: five unlabelled icons would be a
    // puzzle for the person using this app.
    for (final String label in <String>[
      'Home',
      'Medicine',
      'Tests',
      'Doctors',
      'Account',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the tests tab is reachable from the root',
      (WidgetTester tester) async {
    await pumpSignedInApp(tester);

    await tester.tap(find.text('Tests'));
    await tester.pumpAndSettle();

    // The check-ins are the second half of the tests tab.
    await tester.tap(find.text('Check-ins'));
    await tester.pumpAndSettle();
    expect(find.text('Record a check-in'), findsOneWidget);
  });

  testWidgets('doctor linking is reachable from the root',
      (WidgetTester tester) async {
    await pumpSignedInApp(tester);

    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();

    expect(find.text('Care team'), findsOneWidget);
    expect(find.text('Add your doctor'), findsOneWidget);
  });

  testWidgets('the account is reachable from the root',
      (WidgetTester tester) async {
    await pumpSignedInApp(tester);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Log out'), findsOneWidget);
  });
}
