import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/auth/presentation/login_screen.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../test_support.dart';

Widget wrapLoginScreen({MockClient? mockClient}) {
  final PatientControllers controllers = mockClient == null
      ? controllersWith(
          (http.Request request) async => http.Response('{}', 200))
      : controllersWithClient(mockClient);

  return patientScope(
    controllers: controllers,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: LoginScreen(onShowSignUp: () {}),
    ),
  );
}

void main() {
  testWidgets('asks for credentials when the form is submitted empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrapLoginScreen());

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('shows the API message when credentials are rejected',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapLoginScreen(
        mockClient: MockClient(
          (http.Request request) async => http.Response(
            '{"detail": "Invalid email or password."}',
            401,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('offers a way to create an account', (WidgetTester tester) async {
    await tester.pumpWidget(wrapLoginScreen());

    expect(find.text('Create account'), findsOneWidget);
  });
}
