import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/app.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';
import 'package:neurosync_patient/features/check_ins/data/check_in_repository.dart';
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';

const String _patientJson =
    '{"id": 1, "email": "ada@example.com", "name": "Ada Lovelace", '
    '"created_at": "2026-01-01T10:00:00Z"}';

/// Pumps the real [NeuroSyncApp] with a stored session, so the root decides
/// what a signed-in patient actually sees.
Widget signedInApp() {
  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient((http.Request request) async {
      if (request.url.path == '/auth/me') {
        return http.Response(_patientJson, 200);
      }
      // Every list endpoint answers empty; the root only needs them to settle.
      return http.Response('[]', 200);
    }),
    sessionToken: tokenCache,
  );

  return NeuroSyncApp(
    authController: AuthController(
      repository: AuthRepository(apiClient: apiClient),
      tokenStore: InMemorySessionTokenStore('stored-token'),
      tokenCache: tokenCache,
    ),
    doctorLinkController: DoctorLinkController(
        repository: DoctorLinkRepository(apiClient: apiClient)),
    checkInController:
        CheckInController(repository: CheckInRepository(apiClient: apiClient)),
    monitoringController: MonitoringController(
        repository: MonitoringRepository(apiClient: apiClient)),
    medicationController: MedicationController(
        repository: MedicationRepository(apiClient: apiClient)),
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
    // appeared and the check-ins and doctor-linking tabs were unreachable.
    await pumpSignedInApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Check-ins'), findsOneWidget);
    expect(find.text('Doctors'), findsOneWidget);
  });

  testWidgets('check-ins are reachable from the root',
      (WidgetTester tester) async {
    await pumpSignedInApp(tester);

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
}
