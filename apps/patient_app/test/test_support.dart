import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/app_scope.dart';
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

/// The base URL every test talks to. The API is mocked, so it is never reached.
const String kTestBaseUrl = 'http://api.test';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// The signed-in patient, as the API returns them.
Map<String, dynamic> patientJson({
  int id = 1,
  String email = 'ada@example.com',
  String name = 'Ada Lovelace',
}) =>
    <String, dynamic>{
      'id': id,
      'email': email,
      'name': name,
      'created_at': '2026-01-01T10:00:00Z',
    };

/// The controllers a screen needs, all wired to one API client.
///
/// The real controllers, so a test exercises the same wiring the application
/// uses rather than a stand-in for it. The API client and the sign-in
/// controller share one token cache, as `main.dart` wires them: two caches
/// would silently drop the Authorization header instead of failing loudly.
class PatientControllers {
  PatientControllers({
    required http.Client httpClient,
    SessionTokenCache? tokenCache,
    SessionTokenStore? tokenStore,
  })  : tokenCache = tokenCache ?? SessionTokenCache(),
        tokenStore = tokenStore ?? InMemorySessionTokenStore() {
    apiClient = ApiClient(
      baseUrl: kTestBaseUrl,
      httpClient: httpClient,
      sessionToken: this.tokenCache,
    );
    auth = AuthController(
      repository: AuthRepository(apiClient: apiClient),
      tokenStore: this.tokenStore,
      tokenCache: this.tokenCache,
    );
    doctorLinks = DoctorLinkController(
      repository: DoctorLinkRepository(apiClient: apiClient),
    );
    checkIns = CheckInController(
      repository: CheckInRepository(apiClient: apiClient),
    );
    monitoring = MonitoringController(
      repository: MonitoringRepository(apiClient: apiClient),
    );
    medications = MedicationController(
      repository: MedicationRepository(apiClient: apiClient),
    );
  }

  final SessionTokenCache tokenCache;
  final SessionTokenStore tokenStore;

  late final ApiClient apiClient;
  late final AuthController auth;
  late final DoctorLinkController doctorLinks;
  late final CheckInController checkIns;
  late final MonitoringController monitoring;
  late final MedicationController medications;
}

/// Builds the controllers around a scripted API.
PatientControllers controllersWith(
  Future<http.Response> Function(http.Request request) handler, {
  String? storedToken,
}) =>
    PatientControllers(
      httpClient: MockClient(handler),
      tokenStore: InMemorySessionTokenStore(storedToken),
    );

/// Builds the controllers around an HTTP client the test has already scripted.
PatientControllers controllersWithClient(
  http.Client httpClient, {
  String? storedToken,
}) =>
    PatientControllers(
      httpClient: httpClient,
      tokenStore: InMemorySessionTokenStore(storedToken),
    );

/// The signed-in shell, with every controller wired to [apiClient].
Widget patientScope({
  required PatientControllers controllers,
  required Widget child,
  AuthController? authController,
  ThemeController? themeController,
}) {
  return AppScope(
    auth: authController ?? controllers.auth,
    doctorLinks: controllers.doctorLinks,
    checkIns: controllers.checkIns,
    monitoring: controllers.monitoring,
    medications: controllers.medications,
    theme: themeController ?? ThemeController(),
    child: child,
  );
}

/// Pumps [home] inside the real application scope, backed by a scripted API.
Future<AuthController> pumpPatientScreen(
  WidgetTester tester, {
  required Widget home,
  required Future<http.Response> Function(http.Request request) handler,
  bool signedIn = true,
  Size viewport = const Size(393, 852),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);

  final PatientControllers controllers = controllersWith(
    handler,
    storedToken: signedIn ? 'seeded-token' : null,
  );

  await tester.pumpWidget(
    patientScope(
      controllers: controllers,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controllers.auth;
}
