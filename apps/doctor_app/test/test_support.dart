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
import 'package:neurosync_doctor/features/exceptions/data/exception_repository.dart';
import 'package:neurosync_doctor/features/exceptions/state/exception_controller.dart';
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

Map<String, dynamic> pendingRequestJson(
        {int id = 12, String name = 'Jonas Keller'}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 41,
      'patient_name': name,
      'created_at': '2026-09-30T08:00:00Z',
    };

Map<String, dynamic> rosterPatientJson(
        {int id = 41, String name = 'Maya Lindqvist'}) =>
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
  String assessmentSlug = 'finger_tapping',
  String assessmentTitle = 'Finger Tapping',
  String status = 'active',
  Map<String, Object>? parameters,
}) =>
    <String, dynamic>{
      'id': id,
      'title': title,
      'status': status,
      'created_at': '2026-09-30T10:30:00Z',
      'updated_at': '2026-09-30T10:30:00Z',
      'assessment_slug': assessmentSlug,
      'assessment_title': assessmentTitle,
      'duration_seconds': durationSeconds,
      'parameters': parameters ??
          <String, Object>{
            'hand': 'right',
            'finger': 'index',
            'pacing': 'comfortable'
          },
    };

/// A catalog entry, shaped exactly as `GET /doctor/assessments` returns it.
Map<String, dynamic> assessmentJson({
  int id = 1,
  String slug = 'finger_tapping',
  String title = 'Finger Tapping',
  String executionType = 'tap_task',
  bool isSupported = true,
  List<Map<String, Object>> parameters = const <Map<String, Object>>[],
}) =>
    <String, dynamic>{
      'id': id,
      'slug': slug,
      'title': title,
      'description': 'Tap as regularly as you can.',
      'instructions': 'Tap the pad with the finger indicated on screen.',
      'execution_type': executionType,
      'default_duration_seconds': 30,
      'is_supported': isSupported,
      'parameters': parameters,
    };

Map<String, Object> choiceParameter(
  String key,
  String label,
  Object defaultValue,
  List<String> choices, {
  Map<String, String> choiceLabels = const <String, String>{},
  String? valueFormat,
}) =>
    <String, Object>{
      'key': key,
      'label': label,
      'kind': 'choice',
      'default': defaultValue,
      'choices': choices,
      'help_text': 'How $label.toLowerCase() is set.',
      'choice_labels': choiceLabels,
      if (valueFormat != null) 'value_format': valueFormat,
    };

Map<String, Object> integerParameter(
  String key,
  String label,
  int defaultValue,
  int minimum,
  int maximum, {
  String? valueFormat,
}) =>
    <String, Object>{
      'key': key,
      'label': label,
      'kind': 'integer',
      'default': defaultValue,
      'minimum': minimum,
      'maximum': maximum,
      'help_text': 'How $label.toLowerCase() is set.',
      'choice_labels': <String, String>{},
      if (valueFormat != null) 'value_format': valueFormat,
    };

Map<String, Object> textParameter(
  String key,
  String label,
  String defaultValue,
  int maxLength, {
  String? valueFormat,
}) =>
    <String, Object>{
      'key': key,
      'label': label,
      'kind': 'text',
      'default': defaultValue,
      'max_length': maxLength,
      'help_text': 'How $label.toLowerCase() is set.',
      'choice_labels': <String, String>{},
      if (valueFormat != null) 'value_format': valueFormat,
    };

/// The four catalog entries, as the backend seeds them.
List<Map<String, dynamic>> assessmentCatalogJson() => <Map<String, dynamic>>[
      assessmentJson(
        id: 1,
        slug: 'finger_tapping',
        title: 'Finger Tapping',
        parameters: <Map<String, Object>>[
          choiceParameter(
            'hand', 'Hand', 'right', <String>['left', 'right'],
            choiceLabels: <String, String>{'left': 'Left hand', 'right': 'Right hand'},
            valueFormat: '{value} hand',
          ),
          choiceParameter(
            'finger', 'Finger', 'index',
            <String>['thumb', 'index', 'middle', 'ring', 'little'],
            choiceLabels: <String, String>{
              'thumb': 'Thumb', 'index': 'Index', 'middle': 'Middle',
              'ring': 'Ring', 'little': 'Little',
            },
            valueFormat: '{value} finger',
          ),
          choiceParameter(
            'pacing', 'Speed', 'comfortable',
            <String>['slow', 'comfortable', 'fast'],
            choiceLabels: <String, String>{
              'slow': 'Slow', 'comfortable': 'Comfortable', 'fast': 'Fast',
            },
            valueFormat: '{value}',
          ),
        ],
      ),
      assessmentJson(
        id: 2,
        slug: 'spiral_drawing',
        title: 'Spiral Drawing',
        executionType: 'canvas_task',
        // Held back by the backend until its guide is good enough to ask a
        // patient to use. The fixture mirrors the API so the app is tested
        // against the catalog doctors actually get.
        isSupported: false,
        parameters: <Map<String, Object>>[
          choiceParameter(
            'pacing', 'Speed', 'comfortable',
            <String>['slow', 'comfortable', 'fast'],
            choiceLabels: <String, String>{
              'slow': 'Slow', 'comfortable': 'Comfortable', 'fast': 'Fast',
            },
            valueFormat: '{value}',
          ),
          integerParameter('turns', 'Turns', 2, 1, 6, valueFormat: '{value} turn(s)'),
          integerParameter('size_percent', 'Spiral size', 70, 40, 100, valueFormat: '{value}% of screen'),
        ],
      ),
      assessmentJson(
        id: 3,
        slug: 'line_tracing',
        title: 'Line Tracing',
        executionType: 'canvas_task',
        parameters: <Map<String, Object>>[
          choiceParameter(
            'pacing', 'Speed', 'comfortable',
            <String>['slow', 'comfortable', 'fast'],
            choiceLabels: <String, String>{
              'slow': 'Slow', 'comfortable': 'Comfortable', 'fast': 'Fast',
            },
            valueFormat: '{value}',
          ),
          integerParameter('repetitions', 'Repetitions', 3, 1, 10, valueFormat: '{value} time(s)'),
          integerParameter('line_length_percent', 'Line length', 70, 30, 100, valueFormat: '{value}% of screen'),
        ],
      ),
      assessmentJson(
        id: 4,
        slug: 'handwriting',
        title: 'Handwriting',
        executionType: 'canvas_task',
        isSupported: false,
        parameters: <Map<String, Object>>[
          choiceParameter(
            'pacing', 'Speed', 'comfortable',
            <String>['slow', 'comfortable', 'fast'],
            choiceLabels: <String, String>{
              'slow': 'Slow', 'comfortable': 'Comfortable', 'fast': 'Fast',
            },
            valueFormat: '{value}',
          ),
          textParameter('phrase', 'Phrase', 'NeuroSync', 60, valueFormat: '"{value}"'),
          integerParameter('repetitions', 'Repetitions', 1, 1, 5, valueFormat: '{value} time(s)'),
        ],
      ),
    ];

Map<String, dynamic> exceptionSummaryJson({
  int id = 7,
  int patientId = 41,
  String patientName = 'Maya Lindqvist',
  String exceptionType = 'persistent_change',
  String status = 'open',
  String evidenceStrength = 'moderate',
  String createdAt = '2026-09-30T11:15:00Z',
}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': patientId,
      'patient_name': patientName,
      'exception_type': exceptionType,
      'status': status,
      'rationale': "Repeated change from the patient's own baseline across 3 "
          'consecutive usable sessions.',
      'created_at': createdAt,
      'longitudinal_state': 'changed',
      'evidence_strength': evidenceStrength,
      'assessment_title': 'Finger Tapping',
      'medication_context': 'unknown',
      'minutes_since_medication': null,
    };

Map<String, dynamic> exceptionDetailJson({
  int id = 7,
  int patientId = 41,
  String patientName = 'Maya Lindqvist',
  String exceptionType = 'persistent_change',
  String status = 'open',
  String? reviewNote,
  String? reviewedAt,
  int? reviewedByDoctorId,
}) =>
    <String, dynamic>{
      'summary': exceptionSummaryJson(
        id: id,
        patientId: patientId,
        patientName: patientName,
        exceptionType: exceptionType,
        status: status,
      ),
      'routing_rule': 'repeated_change',
      'supporting_observations': 3,
      'longitudinal_result_id': 19,
      'monitoring_session_id': 19,
      'usable_history_count': 7,
      'baseline_confidence': 'full',
      'changed_features': <String>[
        'taps_per_second',
        'mean_inter_tap_interval_ms',
      ],
      'recording_quality': 'valid',
      'total_taps': 10,
      'duration_ms': 27000,
      'taps_per_second': 0.37,
      'mean_inter_tap_interval_ms': 3000,
      'inter_tap_variability_ms': 120,
      'longest_pause_ms': 3000,
      'baseline': <String, dynamic>{
        'observation_count': 8,
        'confidence': 'full',
        'taps_per_second': 0.7,
        'mean_inter_tap_interval_ms': 2000,
        'inter_tap_variability_ms': 90,
        'longest_pause_ms': 2000,
      },
      'reviewed_by_doctor_id': reviewedByDoctorId,
      'reviewed_at': reviewedAt,
      'review_note': reviewNote,
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
  Size viewport = const Size(1280, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
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
      roster:
          RosterController(repository: RosterRepository(apiClient: apiClient)),
      assignments: AssignmentController(
          repository: AssignmentRepository(apiClient: apiClient)),
      exceptions: ExceptionController(
          repository: ExceptionRepository(apiClient: apiClient)),
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}
