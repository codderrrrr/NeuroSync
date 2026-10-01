import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/features/auth/presentation/signup_screen.dart';
import 'package:neurosync_doctor/features/auth/state/auth_controller.dart';

import '../../test_support.dart';

void main() {
  Future<void> pumpSignup(WidgetTester tester,
      Future<http.Response> Function(http.Request) handler) {
    return pumpDoctorScreen(
      tester,
      signedIn: false,
      home: const SignupScreen(),
      handler: handler,
    );
  }

  testWidgets('requires a name, an email and a 12-character password',
      (WidgetTester tester) async {
    await pumpSignup(
        tester, (http.Request request) async => json(<String, dynamic>{}));

    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. Amara Osei');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'amara@clinic.example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 12 characters.'), findsOneWidget);
  });

  testWidgets('signing up signs the doctor in with their link code',
      (WidgetTester tester) async {
    final List<http.Request> requests = <http.Request>[];
    final AuthController auth = await pumpSignup(
      tester,
      (http.Request request) async {
        requests.add(request);
        return json(authBody(), 201);
      },
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. Amara Osei');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'amara@clinic.example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'a-very-long-password');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/doctor/auth/signup');
    final Map<String, dynamic> body =
        jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['name'], 'Dr. Amara Osei');
    expect(body['email'], 'amara@clinic.example.com');

    expect(auth.status, AuthStatus.signedIn);
    expect(auth.doctor?.code, kDoctorCode);
  });

  testWidgets('shows the API error when the email is already registered',
      (WidgetTester tester) async {
    await pumpSignup(
      tester,
      (http.Request request) async => json(
        <String, dynamic>{'detail': 'An account with this email already exists.'},
        409,
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. Amara Osei');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'amara@clinic.example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'a-very-long-password');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email already exists.'),
      findsOneWidget,
    );
  });
}
