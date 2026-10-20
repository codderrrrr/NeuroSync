import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/monitoring/canvas/canvas_ink.dart';
import 'package:neurosync_patient/features/monitoring/canvas/canvas_runner_screen.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/models/monitoring_plan.dart';
import 'package:neurosync_patient/features/monitoring/models/monitoring_session.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

Map<String, dynamic> settingJson(
  String key,
  String label,
  String kind,
  Object defaultValue, {
  List<String> choices = const <String>[],
}) =>
    <String, dynamic>{
      'key': key,
      'label': label,
      'kind': kind,
      'default': defaultValue,
      'choices': choices,
    };

/// The catalog entry, shaped exactly as the API returns it.
Map<String, dynamic> lineTracingAssessmentJson() => <String, dynamic>{
      'id': 3,
      'slug': 'line_tracing',
      'title': 'Line Tracing',
      'description': 'Follow a line between two points.',
      'instructions': 'Trace the path between the two markers.',
      'execution_type': 'canvas_task',
      'default_duration_seconds': 30,
      'is_supported': true,
      'parameters': <Map<String, dynamic>>[
        settingJson('pacing', 'Speed', 'choice', 'comfortable',
            choices: <String>['slow', 'comfortable', 'fast']),
        settingJson('repetitions', 'Repetitions', 'integer', 3),
        settingJson('line_length_percent', 'Line length', 'integer', 70),
      ],
    };

MonitoringPlanItem lineTracingItem({Map<String, Object>? parameters}) =>
    MonitoringPlanItem.fromJson(<String, dynamic>{
      'id': 11,
      'assessment': lineTracingAssessmentJson(),
      'position': 0,
      'completed_today': 0,
      'duration_seconds': 30,
      'parameters': parameters ??
          <String, Object>{
            'pacing': 'slow',
            'repetitions': 3,
            'line_length_percent': 70,
          },
    });

/// The in-progress session the backend opens, before anything is recorded.
Map<String, dynamic> _startBody() => <String, dynamic>{
      'id': 5,
      'status': 'in_progress',
      'assessment': lineTracingAssessmentJson(),
      'started_at': '2026-06-18T10:00:00Z',
      'completed_at': null,
      'result': null,
      'longitudinal': null,
    };

/// The completed session the backend returns for a tracing recording.
Map<String, dynamic> _completeBody() => <String, dynamic>{
      'id': 5,
      'status': 'completed',
      'assessment': lineTracingAssessmentJson(),
      'started_at': '2026-06-18T10:00:00Z',
      'completed_at': '2026-06-18T10:00:30Z',
      'result': <String, dynamic>{
        'quality': 'valid',
        'taps': null,
        'canvas': <String, dynamic>{
          'total_points': 180,
          'stroke_count': 3,
          'duration_ms': 29000,
          'longest_pause_ms': 40,
          'path_length': 1200.0,
          'mean_speed_px_per_second': 300.0,
          'peak_speed_px_per_second': 420.0,
          'path_efficiency': 1.05,
        },
      },
      // No longitudinal comparison exists for a tracing test yet, and the app
      // must not invent one.
      'longitudinal': null,
    };

void main() {
  late List<http.Request> requests;

  /// Whatever the runner handed back when it finished a submission.
  final List<MonitoringSession> handedBack = <MonitoringSession>[];

  Future<MonitoringController> pumpRunner(
    WidgetTester tester, {
    MonitoringPlanItem? item,
  }) async {
    handedBack.clear();
    requests = <http.Request>[];
    final SessionTokenCache tokenCache = SessionTokenCache();
    final ApiClient apiClient = ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.path.endsWith('/complete')) {
          return http.Response(jsonEncode(_completeBody()), 200);
        }
        return http.Response(jsonEncode(_startBody()), 201);
      }),
      sessionToken: tokenCache,
    );
    final MonitoringController controller = MonitoringController(
      repository: MonitoringRepository(apiClient: apiClient),
    );
    await controller.startSession(item ?? lineTracingItem());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: CanvasRunnerScreen(
          controller: controller,
          item: item ?? lineTracingItem(),
          onCompleted: handedBack.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('shows the settings the doctor chose before the patient starts',
      (WidgetTester tester) async {
    await pumpRunner(tester);

    expect(find.text('YOUR DOCTOR SET THIS TEST UP AS'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
    expect(find.text('3 times'), findsOneWidget);
    expect(find.text('This takes about 30 seconds.'), findsOneWidget);
  });

  testWidgets('submits the captured stroke as canvas events, never as taps',
      (WidgetTester tester) async {
    await pumpRunner(tester);

    await tester.tap(find.text('Start test'));
    await tester.pump();

    // Three passes across the canvas, exactly as many as the doctor asked for.
    for (int pass = 0; pass < 3; pass++) {
      await tester.timedDragFrom(
        const Offset(60, 300),
        const Offset(260, 300),
        const Duration(milliseconds: 40),
      );
      await tester.pump();
    }

    // Every requested pass is drawn, so the runner says so and offers to send
    // rather than making the patient sit out the rest of the window.
    expect(find.text('Finish and send now'), findsNothing);
    expect(find.text('All done — finish and send'), findsOneWidget);
    await tester.tap(find.text('All done — finish and send'));
    await tester.pumpAndSettle();

    final http.Request complete = requests
        .lastWhere((http.Request r) => r.url.path.endsWith('/complete'));
    final Map<String, dynamic> body =
        jsonDecode(complete.body) as Map<String, dynamic>;
    final List<dynamic> events = body['events'] as List<dynamic>;

    expect(handedBack.single.result?.canvas?.strokeCount, 3);
    // Every event is a stroke event carrying a coordinate: a tracing recording
    // is never reduced to tap offsets.
    expect(events, isNotEmpty);
    expect(
      events.every(
        (dynamic e) => (e as Map<String, dynamic>)['event_type']
            .toString()
            .startsWith('stroke_'),
      ),
      isTrue,
    );
    expect(
      events.every(
        (dynamic e) => (e as Map<String, dynamic>)['payload'] is Map,
      ),
      isTrue,
    );
  });

  testWidgets('counts the passes out loud as the patient draws them',
      (WidgetTester tester) async {
    await pumpRunner(tester);

    await tester.tap(find.text('Start test'));
    await tester.pump();

    // Nothing drawn yet: the tracker points at the first line.
    expect(find.text('Line 1 of 3'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(60, 300),
      const Offset(260, 300),
      const Duration(milliseconds: 40),
    );
    await tester.pump();
    expect(find.text('Line 2 of 3'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(60, 300),
      const Offset(260, 300),
      const Duration(milliseconds: 40),
    );
    await tester.pump();
    expect(find.text('Line 3 of 3'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(60, 300),
      const Offset(260, 300),
      const Duration(milliseconds: 40),
    );
    await tester.pump();
    // The doctor asked for three, so the patient is told they are done.
    expect(find.textContaining('All 3 done'), findsOneWidget);
  });

  testWidgets('draws the patient\'s own marks back onto the canvas',
      (WidgetTester tester) async {
    await pumpRunner(tester);

    await tester.tap(find.text('Start test'));
    await tester.pump();

    CanvasInkPainter ink() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((CustomPaint paint) => paint.painter)
        .whereType<CanvasInkPainter>()
        .single;

    // Nothing drawn yet, so there is nothing to show back.
    expect(ink().strokes, isEmpty);

    await tester.timedDragFrom(
      const Offset(60, 300),
      const Offset(260, 300),
      const Duration(milliseconds: 40),
    );
    await tester.pump();

    // The stroke the patient just made is on screen, with the points they
    // actually moved through rather than a placeholder.
    expect(ink().strokes, hasLength(1));
    expect(ink().strokes.single.length, greaterThan(1));
    expect(ink().pointCount, greaterThan(1));
  });

  testWidgets('a tracing recording reports its own features, not taps',
      (WidgetTester tester) async {
    MonitoringSession session = MonitoringSession.fromJson(_completeBody());

    expect(session.result!.taps, isNull);
    expect(session.result!.canvas!.strokeCount, 3);
    expect(session.result!.movementCount, 3);
    expect(session.result!.movementLabel, 'passes');
    expect(session.result!.durationMs, 29000);
    expect(session.result!.longestPauseMs, 40);
    // No longitudinal comparison exists for a tracing test yet, and the app
    // must not invent one.
    expect(session.longitudinal, isNull);
  });

  test('a canvas result parses from the API shape', () {
    final SessionResult result = SessionResult.fromJson(<String, dynamic>{
      'quality': 'borderline',
      'taps': null,
      'canvas': <String, dynamic>{
        'total_points': 90,
        'stroke_count': 2,
        'duration_ms': 15000,
        'longest_pause_ms': 6000,
        'path_length': 800.0,
        'mean_speed_px_per_second': 250.0,
        'peak_speed_px_per_second': 500.0,
        'path_efficiency': 1.2,
      },
    });

    expect(result.quality, RecordingQuality.borderline);
    expect(result.canvas!.pathLength, 800.0);
    expect(result.canvas!.pathEfficiency, 1.2);
    expect(result.movementCount, 2);
  });

  test('a result with neither block is rejected rather than shown as empty',
      () {
    expect(
      () => SessionResult.fromJson(<String, dynamic>{
        'quality': 'valid',
        'taps': null,
        'canvas': null,
      }),
      throwsFormatException,
    );
  });

  test('the item exposes the doctor\'s settings as readable lines', () {
    final List<({String label, String value})> settings =
        lineTracingItem().settings;

    expect(settings, hasLength(3));
    expect(settings.first.value, 'Slow');
    expect(
      settings.any((({String label, String value}) s) =>
          s.label == 'Repetitions' && s.value == '3 times'),
      isTrue,
    );
  });
}
