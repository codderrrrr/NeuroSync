import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/app_scope.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';
import 'package:neurosync_patient/features/check_ins/data/check_in_repository.dart';
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';
import 'package:neurosync_patient/features/intro/intro_flow.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';

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

Widget wrapIntro(
  AuthController auth,
  DoctorLinkController links,
  CheckInController checkIns,
  MonitoringController monitoring,
  MedicationController medications,
) {
  return AppScope(
    auth: auth,
    doctorLinks: links,
    checkIns: checkIns,
    monitoring: monitoring,
    medications: medications,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const IntroFlow(),
    ),
  );
}

(
  AuthController,
  DoctorLinkController,
  CheckInController,
  MonitoringController,
  MedicationController,
) buildControllers() {
  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient:
        MockClient((http.Request request) async => http.Response('{}', 200)),
    sessionToken: tokenCache,
  );
  final AuthController auth = AuthController(
    repository: AuthRepository(apiClient: apiClient),
    tokenStore: InMemorySessionTokenStore(),
    tokenCache: tokenCache,
  );
  final DoctorLinkController links = DoctorLinkController(
    repository: DoctorLinkRepository(apiClient: apiClient),
  );
  final CheckInController checkIns = CheckInController(
    repository: CheckInRepository(apiClient: apiClient),
  );
  final MedicationController medications = MedicationController(
    repository: MedicationRepository(apiClient: apiClient),
  );

  final MonitoringController monitoring = MonitoringController(
    repository: MonitoringRepository(apiClient: apiClient),
  );
  return (auth, links, checkIns, monitoring, medications);
}

Future<void> passSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch: splash then onboarding',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: false);
    final (
      AuthController auth,
      DoctorLinkController links,
      CheckInController checkIns,
      MonitoringController monitoring,
      MedicationController medications
    ) = buildControllers();
    auth.restoreSession();

    await tester
        .pumpWidget(wrapIntro(auth, links, checkIns, monitoring, medications));
    await passSplash(tester);

    expect(find.text('Understand your movement.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('returning patient goes straight to sign in',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: true);
    final (
      AuthController auth,
      DoctorLinkController links,
      CheckInController checkIns,
      MonitoringController monitoring,
      MedicationController medications
    ) = buildControllers();
    auth.restoreSession();

    await tester
        .pumpWidget(wrapIntro(auth, links, checkIns, monitoring, medications));
    await passSplash(tester);

    expect(find.text('Sign in to continue to your care.'), findsOneWidget);
    expect(find.text('Understand your movement.'), findsNothing);
  });

  testWidgets('onboarding completes into welcome, then into authentication',
      (WidgetTester tester) async {
    _mockSeen(tester, seen: false);
    final (
      AuthController auth,
      DoctorLinkController links,
      CheckInController checkIns,
      MonitoringController monitoring,
      MedicationController medications
    ) = buildControllers();
    auth.restoreSession();

    await tester
        .pumpWidget(wrapIntro(auth, links, checkIns, monitoring, medications));
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
