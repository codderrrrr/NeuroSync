import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// The JSON the API returns for the seeded default plan.
Map<String, dynamic> planJson({bool supported = true}) {
  return <String, dynamic>{
    'id': 1,
    'title': 'Daily motor check-in',
    'status': 'active',
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 11,
        'position': 0,
        'completed_today': 0,
        'assessment': <String, dynamic>{
          'id': 1,
          'slug': 'finger_tapping',
          'title': 'Finger Tapping',
          'description': 'Tap as regularly as you can.',
          'instructions': 'Tap the pad at a steady pace.',
          'execution_type': 'tap_task',
          'default_duration_seconds': 30,
          'is_supported': supported,
        },
      },
    ],
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
    'assessment': planJson()['items'][0]['assessment'],
    'started_at': '2026-06-18T10:00:00Z',
    'completed_at': status == 'completed' ? '2026-06-18T10:00:30Z' : null,
    'result': result,
  };
}

Map<String, dynamic> resultJson({String quality = 'valid'}) {
  return <String, dynamic>{
    'quality': quality,
    'taps': <String, dynamic>{
      'total_taps': 90,
      'duration_ms': 30000,
      'mean_inter_tap_interval_ms': 333,
      'inter_tap_variability_ms': 42,
      'longest_pause_ms': 900,
      'taps_per_second': 3.0,
    },
    'canvas': null,
  };
}

MonitoringController buildController(MockClient mockClient) {
  return MonitoringController(
    repository: MonitoringRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: mockClient,
        sessionToken: SessionTokenCache(),
      ),
    ),
  );
}

void main() {
  test('loading fetches the plan from the API and exposes the next item',
      () async {
    late http.Request captured;
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        captured = request;
        return http.Response(jsonEncode(planJson()), 200);
      }),
    );

    await controller.loadPlan();

    expect(captured.url.path, '/monitoring/plan');
    expect(controller.hasLoadedPlan, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.plan, isNotNull);
    expect(controller.plan!.title, 'Daily motor check-in');
    expect(controller.plan!.items.single.assessment.title, 'Finger Tapping');
    expect(controller.plan!.nextAvailableItem, isNotNull);
  });

  test('a missing plan is a normal state, not an error', () async {
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async => http.Response(
            jsonEncode(<String, dynamic>{
              'detail': 'No active monitoring plan found.'
            }),
            404,
          )),
    );

    await controller.loadPlan();

    expect(controller.hasLoadedPlan, isTrue);
    expect(controller.plan, isNull);
    expect(controller.errorMessage, isNull);
  });

  test('a server failure surfaces the API message', () async {
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Database unavailable.'}),
          500)),
    );

    await controller.loadPlan();

    expect(controller.plan, isNull);
    expect(controller.errorMessage, 'Database unavailable.');
  });

  test('starting a session posts the plan item id', () async {
    late http.Request captured;
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/monitoring/sessions') {
          captured = request;
          return http.Response(jsonEncode(sessionJson(id: 7)), 201);
        }
        return http.Response(jsonEncode(planJson()), 200);
      }),
    );
    await controller.loadPlan();

    final bool started =
        await controller.startSession(controller.plan!.items.single);

    expect(started, isTrue);
    expect(captured.url.path, '/monitoring/sessions');
    final Map<String, dynamic> body =
        jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['plan_item_id'], 11);
    expect(controller.activeSession, isNotNull);
    expect(controller.activeSession!.id, 7);
  });

  test('completing sends tap events and keeps the server result', () async {
    late http.Request captured;
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/monitoring/sessions') {
          return http.Response(jsonEncode(sessionJson(id: 7)), 201);
        }
        if (request.url.path == '/monitoring/sessions/7/complete') {
          captured = request;
          return http.Response(
            jsonEncode(
              sessionJson(
                  id: 7,
                  status: 'completed',
                  result: resultJson(quality: 'valid')),
            ),
            200,
          );
        }
        return http.Response(jsonEncode(planJson()), 200);
      }),
    );
    await controller.loadPlan();
    await controller.startSession(controller.plan!.items.single);

    final bool submitted = await controller.completeSession(<int>[0, 333, 666]);

    expect(submitted, isTrue);
    expect(captured.url.path, '/monitoring/sessions/7/complete');
    final Map<String, dynamic> body =
        jsonDecode(captured.body) as Map<String, dynamic>;
    final List<Map<String, dynamic>> events =
        (body['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(3));
    expect(events.first['event_type'], 'tap');
    expect(events.first['offset_ms'], 0);
    expect(events.last['offset_ms'], 666);

    expect(controller.activeSession, isNull);
    expect(controller.lastCompletedSession, isNotNull);
    expect(controller.lastCompletedSession!.result!.quality,
        RecordingQuality.valid);
    // History is stale once a new session completes.
    expect(controller.hasLoadedHistory, isFalse);
  });

  test('a rejected completion surfaces the error and keeps the session active',
      () async {
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/monitoring/sessions') {
          return http.Response(jsonEncode(sessionJson(id: 7)), 201);
        }
        if (request.method == 'GET' && request.url.path == '/monitoring/plan') {
          return http.Response(jsonEncode(planJson()), 200);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'detail': 'Event offsets must be non-decreasing.'
          }),
          422,
        );
      }),
    );
    await controller.loadPlan();
    await controller.startSession(controller.plan!.items.single);

    final bool submitted = await controller.completeSession(<int>[500, 100]);

    expect(submitted, isFalse);
    expect(controller.errorMessage, 'Event offsets must be non-decreasing.');
    expect(controller.activeSession, isNotNull);
    expect(controller.lastCompletedSession, isNull);
  });

  test('history loads completed sessions newest first', () async {
    late http.Request captured;
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<dynamic>[
            sessionJson(
                id: 9,
                status: 'completed',
                result: resultJson(quality: 'borderline')),
            sessionJson(
                id: 8,
                status: 'completed',
                result: resultJson(quality: 'valid')),
          ]),
          200,
        );
      }),
    );

    await controller.loadHistory();

    expect(captured.url.path, '/monitoring/sessions');
    expect(captured.url.queryParameters['limit'], '30');
    expect(controller.history, hasLength(2));
    expect(controller.history.first.id, 9);
    expect(
        controller.history.first.result!.quality, RecordingQuality.borderline);
    expect(controller.hasLoadedHistory, isTrue);
  });

  test('clearing drops plan, session and history on sign-out', () async {
    final MonitoringController controller = buildController(
      MockClient((http.Request request) async {
        if (request.url.path == '/monitoring/plan') {
          return http.Response(jsonEncode(planJson()), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    await controller.loadPlan();
    await controller.loadHistory();

    controller.clear();

    expect(controller.plan, isNull);
    expect(controller.history, isEmpty);
    expect(controller.hasLoadedPlan, isFalse);
    expect(controller.hasLoadedHistory, isFalse);
  });
}
