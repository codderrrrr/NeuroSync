import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_patient/features/intro/intro_flow.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../test_support.dart';

const MethodChannel _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _mockSeen(WidgetTester tester, {required bool seen}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_secureStorage,
      (MethodCall call) async {
    if (call.method == 'read') {
      return seen ? '1' : null;
    }
    return null;
  });
}

Widget wrapIntro(PatientControllers controllers) {
  return patientScope(
    controllers: controllers,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const IntroFlow(),
    ),
  );
}

PatientControllers buildControllers() => controllersWith(
      (http.Request request) async => http.Response('{}', 200),
    );

Future<void> passSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch: splash then onboarding',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: false);
    final PatientControllers controllers = buildControllers();
    controllers.auth.restoreSession();

    await tester.pumpWidget(wrapIntro(controllers));
    await passSplash(tester);

    expect(find.text('Understand your movement.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('returning patient goes straight to sign in',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: true);
    final PatientControllers controllers = buildControllers();
    controllers.auth.restoreSession();

    await tester.pumpWidget(wrapIntro(controllers));
    await passSplash(tester);

    expect(find.text('Sign in to continue to your care.'), findsOneWidget);
    expect(find.text('Understand your movement.'), findsNothing);
  });

  testWidgets('onboarding completes into welcome, then into authentication',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: false);
    final PatientControllers controllers = buildControllers();
    controllers.auth.restoreSession();

    await tester.pumpWidget(wrapIntro(controllers));
    await passSplash(tester);

    // Skip onboarding.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to NeuroSync.'), findsOneWidget);

    // Welcome into the sign-up form.
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('We only ask for what is needed to sign you in.'),
        findsOneWidget);
  });
}
