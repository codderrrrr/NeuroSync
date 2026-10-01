import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/features/auth/presentation/login_screen.dart';
import 'package:neurosync_doctor/features/auth/presentation/signup_screen.dart';

import '../../test_support.dart';

void main() {
  testWidgets('asks for credentials when the form is submitted empty',
      (WidgetTester tester) async {
    await pumpDoctorScreen(
      tester,
      signedIn: false,
      home: const LoginScreen(),
      handler: (http.Request request) async => json(<String, dynamic>{}),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('shows the API message when credentials are rejected',
      (WidgetTester tester) async {
    await pumpDoctorScreen(
      tester,
      signedIn: false,
      home: const LoginScreen(),
      handler: (http.Request request) async => json(
        <String, dynamic>{'detail': 'Invalid email or password.'},
        401,
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'amara@clinic.example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('offers a way to create a doctor account',
      (WidgetTester tester) async {
    await pumpDoctorScreen(
      tester,
      signedIn: false,
      home: const LoginScreen(),
      handler: (http.Request request) async => json(<String, dynamic>{}),
    );

    await tester.tap(find.text('Create a doctor account'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
  });
}
