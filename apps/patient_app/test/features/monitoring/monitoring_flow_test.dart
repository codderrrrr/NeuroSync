import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:neurosync_patient/features/home/presentation/home_screen.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';
import 'package:neurosync_patient/features/monitoring/presentation/session_result_screen.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';

Map<String, dynamic> assessmentJson({
  String slug = 'finger_tapping',
  String title = 'Finger Tapping',
  bool supported = true,
}) {
  return <String, dynamic>{
    'id': 1,
    'slug': slug,
    'title': title,
    'description': 'Tap as regularly as you can.',
    'instructions': 'Tap the pad at a steady pace.',
    'execution_type': supported ? 'tap_task' : 'canvas_task',
    'default_duration_seconds': 30,
    'is_supported': supported,
  };
}

Map<String, dynamic> planJson({
  bool supported = true,
  int completedToday = 0,
  int durationSeconds = 30,
}) {
  return <String, dynamic>{
    'id': 1,
    'title': 'Daily motor check-in',
    'status': 'active',
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 11,
        'position': 0,
        'completed_today': completedToday,
        'assessment': assessmentJson(supported: supported)
          ..['default_duration_seconds'] = durationSeconds,
      },
    ],
  };
}

/// Shaped exactly as the API returns it: one block, for the runner that
/// captured the session.
Map<String, dynamic> resultJson(String quality) {
  return <String, dynamic>{
    'quality': quality,
    'taps': <String, dynamic>{
      'total_taps': 42,
      'duration_ms': 30000,
      'mean_inter_tap_interval_ms': 700,
      'inter_tap_variability_ms': 90,
      'longest_pause_ms': 2100,
      'taps_per_second': 1.4,
    },
    'canvas': null,
  };
}

Map<String, dynamic> sessionJson({
  required int id,
  String status = 'in_progress',
  Map<String, dynamic>? result,
}) {
  return <String, dynamic>{
    'id': id,
    'status': status,
    'assessment': assessmentJson(),
    'started_at': '2026-06-18T10:00:00Z',
    'completed_at': status == 'completed' ? '2026-06-18T10:00:30Z' : null,
    'result': result,
  };
}

/// Pumps the Home screen wired to a mock API with a scripted handler.
Future<AppScope> pumpHome(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1600);
  addTearDown(tester.view.reset);

  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient(handler),
    sessionToken: tokenCache,
  );
  final AppScope scope = AppScope(
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
    monitoring: MonitoringController(
      repository: MonitoringRepository(apiClient: apiClient),
    ),
    medications: MedicationController(
      repository: MedicationRepository(apiClient: apiClient),
    ),
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    ),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return scope;
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  testWidgets('home shows the next assessment from the API',
      (WidgetTester tester) async {
    await pumpHome(
      tester,
      (http.Request request) async => json(planJson()),
    );

    expect(find.text('Daily motor check-in'), findsOneWidget);
    expect(find.text('Finger Tapping'), findsOneWidget);
    expect(find.text('Begin test'), findsOneWidget);
    expect(find.text('NOT AVAILABLE YET'), findsNothing);
  });

  testWidgets('an unsupported assessment is shown but cannot be launched',
      (WidgetTester tester) async {
    http.Request? startRequest;
    await pumpHome(
      tester,
      (http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/monitoring/sessions') {
          startRequest = request;
          return json(sessionJson(id: 1), 201);
        }
        return json(planJson(supported: false));
      },
    );

    expect(find.text('Spiral Drawing'),
        findsNothing); // the seeded plan is finger tapping
    expect(find.text('NOT AVAILABLE YET'), findsOneWidget);
    expect(find.text('Begin test'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(startRequest, isNull,
        reason: 'no session may start for an unsupported test');
  });

  testWidgets('a plan with everything completed shows all done',
      (WidgetTester tester) async {
    await pumpHome(
      tester,
      (http.Request request) async => json(planJson(completedToday: 1)),
    );

    expect(find.text('All done for today'), findsOneWidget);
    expect(find.text('Begin test'), findsNothing);
  });

  testWidgets('a missing plan shows a quiet explanation',
      (WidgetTester tester) async {
    await pumpHome(
      tester,
      (http.Request request) async => json(
        <String, dynamic>{'detail': 'No active monitoring plan found.'},
        404,
      ),
    );

    expect(find.text('No monitoring plan yet'), findsOneWidget);
    expect(find.text('Begin test'), findsNothing);
  });

  testWidgets(
      'beginning the test opens the runner, taps are sent, result shown',
      (WidgetTester tester) async {
    final List<dynamic> completedBodies = <dynamic>[];
    await pumpHome(
      tester,
      (http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/monitoring/sessions') {
          return json(sessionJson(id: 31), 201);
        }
        if (request.url.path == '/monitoring/sessions/31/complete') {
          completedBodies.add(jsonDecode(request.body));
          return json(
            sessionJson(
                id: 31, status: 'completed', result: resultJson('valid')),
          );
        }
        return json(planJson(durationSeconds: 0));
      },
    );

    await tester.tap(find.text('Begin test'));
    await tester.pumpAndSettle();

    // The runner starts in preparation; starting the recording is explicit.
    expect(find.text('Start test'), findsOneWidget);
    expect(find.text('Tap here'), findsNothing);
    await tester.tap(find.text('Start test'));
    await tester.pump();

    // The tap pad is live.
    expect(find.text('Tap here'), findsOneWidget);
    expect(find.text('0 taps'), findsOneWidget);
    await tester.tap(find.text('Tap here'));
    await tester.tap(find.text('Tap here'));
    await tester.tap(find.text('Tap here'));
    await tester.pump(); // flush the tap-counter frame without advancing time
    expect(find.text('3 taps'), findsOneWidget);

    // The zero-second target auto-finishes on the next tick. The recording is
    // captured first, and the optional medication step is asked for after it:
    // the timing a patient reports is the timing around the test they just did.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    // The step is skippable, and skipping is a complete answer: the session is
    // still submitted, with the medication timing simply left unknown.
    expect(find.text('Medication check'), findsOneWidget);
    await tester.tap(find.text('Continue without'));
    await tester.pumpAndSettle();

    expect(completedBodies, hasLength(1));
    final Map<String, dynamic> body =
        completedBodies.first as Map<String, dynamic>;
    final List<Map<String, dynamic>> events =
        (body['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(3));
    expect(events.first['event_type'], 'tap');
    // Skipping attaches no dose event, and the request says so explicitly
    // rather than omitting the field and leaving it to be guessed.
    expect(body['medication_event_id'], isNull);

    // Back on the result screen: describes the recording, nothing clinical.
    expect(find.byType(SessionResultScreen), findsOneWidget);
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('GOOD RECORDING'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('TAPS RECORDED'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('MORE DETAIL'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('the result screen explains an early-ended recording honestly',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        // The screen is a complete route: it brings its own Scaffold and
        // SafeArea, so a caller must not wrap it again.
        home: SessionResultScreen(
          assessmentTitle: 'Finger Tapping',
          completedAt: DateTime.parse('2026-06-18T10:00:30Z'),
          result: SessionResult.fromJson(resultJson('incomplete')),
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ENDED EARLY'), findsOneWidget);
    expect(
      find.text('The recording ended before enough tapping was captured.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
