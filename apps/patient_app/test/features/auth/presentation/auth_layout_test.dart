import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/app_scope.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/core/widgets/app_buttons.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/presentation/login_screen.dart';
import 'package:neurosync_patient/features/auth/presentation/signup_screen.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';
import 'package:neurosync_patient/features/check_ins/data/check_in_repository.dart';
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';

/// The authentication screens as the first-time experience presents them: the
/// dark theme, on a phone-sized surface.
Future<void> pumpAuthScreen(
  WidgetTester tester, {
  required Widget home,
  Size size = const Size(360, 820),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient:
        MockClient((http.Request request) async => http.Response('{}', 200)),
    sessionToken: tokenCache,
  );

  await tester.pumpWidget(
    AppScope(
      auth: AuthController(
        repository: AuthRepository(apiClient: apiClient),
        tokenStore: InMemorySessionTokenStore(),
        tokenCache: tokenCache,
      ),
      doctorLinks: DoctorLinkController(
        repository: DoctorLinkRepository(apiClient: apiClient),
      ),
      checkIns: CheckInController(
        repository: CheckInRepository(apiClient: apiClient),
      ),
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keeps sign-in on screen without scrolling',
      (WidgetTester tester) async {
    await pumpAuthScreen(tester, home: LoginScreen(onShowSignUp: () {}));

    expect(tester.takeException(), isNull);
    final Rect action = tester.getRect(find.text('Sign in'));
    expect(action.top, greaterThan(0));
    expect(action.bottom, lessThanOrEqualTo(820));
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('signs in through a single autofill context',
      (WidgetTester tester) async {
    await pumpAuthScreen(tester, home: LoginScreen(onShowSignUp: () {}));

    expect(find.byType(AutofillGroup), findsOneWidget);
  });

  testWidgets('lets the patient check the password they typed',
      (WidgetTester tester) async {
    await pumpAuthScreen(tester, home: LoginScreen(onShowSignUp: () {}));

    bool obscured() => tester
        .widget<EditableText>(find.byType(EditableText).at(1))
        .obscureText;

    expect(obscured(), isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(obscured(), isFalse);
  });

  testWidgets('keeps account creation on screen without scrolling',
      (WidgetTester tester) async {
    await pumpAuthScreen(tester, home: SignUpScreen(onShowSignIn: () {}));

    expect(tester.takeException(), isNull);
    final Rect action = tester.getRect(
      find.widgetWithText(PrimaryButton, 'Create account'),
    );
    expect(action.top, greaterThan(0));
    expect(action.bottom, lessThanOrEqualTo(820));
    expect(find.byType(AutofillGroup), findsOneWidget);
  });

  testWidgets('stays usable at the largest system text scale',
      (WidgetTester tester) async {
    await pumpAuthScreen(
      tester,
      home: SignUpScreen(onShowSignIn: () {}),
      textScale: 1.6,
    );

    // Scrollable by design at this size, but never broken.
    expect(tester.takeException(), isNull);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });
}
