import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/app_scope.dart';
import 'package:neurosync_doctor/core/network/api_client.dart';
import 'package:neurosync_doctor/core/storage/session_token_store.dart';
import 'package:neurosync_doctor/core/theme/app_theme.dart';
import 'package:neurosync_doctor/features/auth/data/auth_repository.dart';
import 'package:neurosync_doctor/features/auth/state/auth_controller.dart';
import 'package:neurosync_doctor/features/patients/data/assignment_repository.dart';
import 'package:neurosync_doctor/features/patients/state/assignment_controller.dart';
import 'package:neurosync_doctor/features/roster/data/roster_repository.dart';
import 'package:neurosync_doctor/features/roster/state/roster_controller.dart';

/// A code-shaped fixture value matching the backend's unambiguous alphabet.
const String kDoctorCode = 'K7M2XQ9';

Map<String, dynamic> doctorJson({String? code = kDoctorCode}) =>
    <String, dynamic>{
      'id': 3,
      'name': 'Dr. Amara Osei',
      'email': 'amara@clinic.example.com',
      'created_at': '2026-09-30T09:00:00Z',
      'code': code,
    };

Map<String, dynamic> authBody({String? code = kDoctorCode}) =>
    <String, dynamic>{
      'access_token': 'test-session-token',
      'expires_at': '2026-10-07T09:00:00Z',
      'doctor': doctorJson(code: code),
    };

Map<String, dynamic> pendingRequestJson({int id = 12, String name = 'Jonas Keller'}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 41,
      'patient_name': name,
      'created_at': '2026-09-30T08:00:00Z',
    };

Map<String, dynamic> rosterPatientJson({int id = 41, String name = 'Maya Lindqvist'}) =>
    <String, dynamic>{
      'patient_id': id,
      'patient_name': name,
      'status': 'active',
      'linked_at': '2026-09-28T12:00:00Z',
    };

Map<String, dynamic> assignmentJson({
  int id = 77,
  String title = 'Finger Tapping',
  int durationSeconds = 60,
}) =>
    <String, dynamic>{
      'id': id,
      'title': title,
      'status': 'active',
      'created_at': '2026-09-30T10:30:00Z',
      'assessment_title': 'Finger Tapping',
      'duration_seconds': durationSeconds,
    };

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// Pumps [home] inside the real AppScope wiring, backed by a scripted API.
///
/// By default a signed-in doctor is seeded by answering `GET /doctor/auth/me`,
/// exactly the restore path the app uses at launch. Pass [signedIn: false] for
/// auth screens.
Future<AuthController> pumpDoctorScreen(
  WidgetTester tester, {
  required Widget home,
  required Future<http.Response> Function(http.Request) handler,
  bool signedIn = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1600);
  addTearDown(tester.view.reset);

  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient((http.Request request) async {
      if (signedIn &&
          request.method == 'GET' &&
          request.url.path == '/doctor/auth/me') {
        return json(doctorJson());
      }
      return handler(request);
    }),
    sessionToken: tokenCache,
  );
  final AuthController auth = AuthController(
    repository: AuthRepository(apiClient: apiClient),
    tokenStore: InMemorySessionTokenStore(signedIn ? 'seeded-token' : null),
    tokenCache: tokenCache,
  );
  if (signedIn) {
    await auth.restoreSession();
  }

  await tester.pumpWidget(
    AppScope(
      auth: auth,
      roster: RosterController(
          repository: RosterRepository(apiClient: apiClient)),
      assignments: AssignmentController(
          repository: AssignmentRepository(apiClient: apiClient)),
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}
