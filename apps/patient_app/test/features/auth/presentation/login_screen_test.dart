import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/app_scope.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/presentation/login_screen.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';

Widget wrapLoginScreen({MockClient? mockClient}) {
  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: mockClient ??
        MockClient((http.Request request) async => http.Response('{}', 200)),
    sessionToken: tokenCache,
  );

  return AppScope(
    auth: AuthController(
      repository: AuthRepository(apiClient: apiClient),
      tokenStore: InMemorySessionTokenStore(),
      tokenCache: tokenCache,
    ),
    doctorLinks: DoctorLinkController(
      repository: DoctorLinkRepository(apiClient: apiClient),
    ),
    child: MaterialApp(
      theme: AppTheme.light(),
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
