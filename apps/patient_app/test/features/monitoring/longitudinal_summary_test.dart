import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/features/medication/models/medication_context.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/models/longitudinal_summary.dart';
import 'package:neurosync_patient/features/monitoring/models/monitoring_session.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';
import 'package:neurosync_patient/features/monitoring/presentation/monitoring_history_section.dart';
import 'package:neurosync_patient/features/monitoring/presentation/session_result_screen.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';

Map<String, dynamic> longitudinalJson({
  String state = 'within_baseline',
  int usableHistoryCount = 3,
  int? baselineObservationCount = 3,
  String? baselineConfidence = 'full',
  List<String> changedFeatures = const <String>[],
  bool isConfident = true,
  String medicationContext = 'unknown',
  String? medicationName,
  int? minutesSinceMedication,
  String evidenceStrength = 'moderate',
  int comparableObservationCount = 0,
  String? medicationNote,
}) {
  return <String, dynamic>{
    'state': state,
    'usable_history_count': usableHistoryCount,
    'baseline_observation_count': baselineObservationCount,
    'baseline_confidence': baselineConfidence,
    'changed_features': changedFeatures,
    'is_confident': isConfident,
    'medication_context': medicationContext,
    'medication_name': medicationName,
    'minutes_since_medication': minutesSinceMedication,
    'evidence_strength': evidenceStrength,
    'comparable_observation_count': comparableObservationCount,
    'medication_note': medicationNote ??
        'Medication timing was not available for this assessment.',
  };
}

/// Shaped exactly as the API returns it: one block, for the runner that
/// captured the session.
Map<String, dynamic> resultJson(String quality) => <String, dynamic>{
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

Map<String, dynamic> sessionJson({
  required int id,
  Map<String, dynamic>? longitudinal,
  String quality = 'valid',
}) {
  return <String, dynamic>{
    'id': id,
    'status': 'completed',
    'assessment': <String, dynamic>{
      'id': 1,
      'slug': 'finger_tapping',
      'title': 'Finger Tapping',
      'description': 'Tap as regularly as you can.',
      'instructions': 'Tap the pad at a steady pace.',
      'execution_type': 'tap_task',
      'default_duration_seconds': 30,
      'is_supported': true,
    },
    'started_at': '2026-06-18T10:00:00Z',
    'completed_at': '2026-06-18T10:00:30Z',
    'result': resultJson(quality),
    'longitudinal': longitudinal,
  };
}

SessionResult sampleResult() => SessionResult(
      quality: RecordingQuality.valid,
      taps: const TapResult(
        totalTaps: 42,
        durationMs: 30000,
        meanInterTapIntervalMs: 700,
        interTapVariabilityMs: 90,
        longestPauseMs: 2100,
        tapsPerSecond: 1.4,
      ),
    );

Future<void> pumpResult(
  WidgetTester tester,
  LongitudinalSummary summary,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: SessionResultScreen(
        assessmentTitle: 'Finger Tapping',
        completedAt: DateTime.parse('2026-06-18T10:00:30Z'),
        result: sampleResult(),
        longitudinal: summary,
        onDone: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LongitudinalState', () {
    test('parses every state the backend can send', () {
      expect(
        LongitudinalState.fromApi('insufficient_data'),
        LongitudinalState.insufficientData,
      );
      expect(
        LongitudinalState.fromApi('within_baseline'),
        LongitudinalState.withinBaseline,
      );
      expect(LongitudinalState.fromApi('changed'), LongitudinalState.changed);
      expect(LongitudinalState.fromApi('unreliable'),
          LongitudinalState.unreliable);
    });

    test('rejects an unknown state rather than guessing', () {
      expect(
        () => LongitudinalState.fromApi('worsening'),
        throwsFormatException,
      );
    });

    test('never uses diagnosis or progression language', () {
      for (final LongitudinalState state in LongitudinalState.values) {
        final String text =
            '${state.label} ${state.explanation} ${state.shortLabel}'
                .toLowerCase();
        for (final String forbidden in <String>[
          'diagnos',
          'deteriorat',
          'progress',
          'worsen',
          'stage',
          'severity',
          'treatment',
        ]) {
          expect(text.contains(forbidden), isFalse,
              reason: '$state: $forbidden');
        }
      }
    });
  });

  group('LongitudinalSummary', () {
    test('parses the API payload', () {
      final LongitudinalSummary summary = LongitudinalSummary.fromJson(
        longitudinalJson(
          state: 'changed',
          changedFeatures: <String>['mean_inter_tap_interval_ms'],
        ),
      );

      expect(summary.state, LongitudinalState.changed);
      expect(summary.usableHistoryCount, 3);
      expect(summary.baselineConfidence, 'full');
      expect(summary.changedFeatures, <String>['mean_inter_tap_interval_ms']);
      expect(summary.isConfident, isTrue);
    });

    test('describes how much history the state rests on', () {
      expect(
        LongitudinalSummary.fromJson(longitudinalJson()).historyContext,
        'Compared with 3 earlier sessions of your own recordings.',
      );
      expect(
        LongitudinalSummary.fromJson(
          longitudinalJson(usableHistoryCount: 1, baselineObservationCount: 1),
        ).historyContext,
        'Compared with 1 earlier session of your own recordings.',
      );
      expect(
        LongitudinalSummary.fromJson(
          longitudinalJson(
            usableHistoryCount: 0,
            baselineObservationCount: null,
            baselineConfidence: null,
            isConfident: false,
          ),
        ).historyContext,
        'No earlier sessions to compare with yet.',
      );
    });

    test('only notes reduced confidence when the baseline is reduced', () {
      expect(
        LongitudinalSummary.fromJson(longitudinalJson()).confidenceNote,
        isNull,
      );
      expect(
        LongitudinalSummary.fromJson(
          longitudinalJson(baselineConfidence: 'reduced', isConfident: false),
        ).confidenceNote,
        contains('less certain'),
      );
    });

    test('tolerates a missing changed_features list', () {
      final LongitudinalSummary summary = LongitudinalSummary.fromJson(
        <String, dynamic>{
          'state': 'within_baseline',
          'usable_history_count': 3,
          'baseline_observation_count': 3,
          'baseline_confidence': 'full',
          'is_confident': true,
        },
      );
      expect(summary.changedFeatures, isEmpty);
    });

    test('a payload from before the medication layer still parses', () {
      // The earlier contract fixture has no medication block at all. Absence
      // must read as "unknown", never as an accidental known window.
      final LongitudinalSummary summary = LongitudinalSummary.fromJson(
        <String, dynamic>{
          'state': 'within_baseline',
          'usable_history_count': 3,
          'baseline_observation_count': 3,
          'baseline_confidence': 'full',
          'changed_features': <String>[],
          'is_confident': true,
        },
      );

      expect(summary.medicationContext, MedicationContext.unknown);
      expect(summary.medicationName, isNull);
      expect(summary.minutesSinceMedication, isNull);
      expect(summary.evidenceStrength, EvidenceStrength.insufficient);
      expect(summary.timingLabel, isNull);
      expect(summary.medicationNote, isNotEmpty);
    });

    test('parses the medication context the backend derived', () {
      final LongitudinalSummary summary = LongitudinalSummary.fromJson(
        longitudinalJson(
          medicationContext: 'later_after_medication',
          medicationName: 'Levodopa',
          minutesSinceMedication: 150,
          evidenceStrength: 'stronger',
          comparableObservationCount: 4,
          medicationNote:
              'This assessment was recorded approximately 2h 30m after the '
              'reported medication.',
        ),
      );

      expect(
        summary.medicationContext,
        MedicationContext.laterAfterMedication,
      );
      expect(summary.medicationName, 'Levodopa');
      expect(summary.minutesSinceMedication, 150);
      expect(summary.evidenceStrength, EvidenceStrength.stronger);
      expect(summary.comparableObservationCount, 4);
      expect(summary.timingLabel, '2h 30m after the reported dose');
    });

    test('renders elapsed time the way a person would say it', () {
      String labelFor(String context, int minutes) =>
          LongitudinalSummary.fromJson(
            longitudinalJson(
              medicationContext: context,
              minutesSinceMedication: minutes,
            ),
          ).timingLabel ??
          '';

      expect(labelFor('recently_after_medication', 25),
          '25 min after the reported dose');
      expect(labelFor('recently_after_medication', 60),
          '1h after the reported dose');
      expect(labelFor('later_after_medication', 105),
          '1h 45m after the reported dose');
      expect(labelFor('later_after_medication', 240),
          '4h after the reported dose');
      expect(
          labelFor('before_medication', 40), '40 min before the reported dose');
      // Direction comes from the context, so an unknown one never shows a
      // number, whichever side of the comparison it was measured from.
      expect(labelFor('unknown', 40), isEmpty);
    });
  });

  group('MonitoringSession', () {
    test('parses the longitudinal block', () {
      final MonitoringSession session = MonitoringSession.fromJson(
        sessionJson(id: 7, longitudinal: longitudinalJson()),
      );

      expect(session.longitudinal?.state, LongitudinalState.withinBaseline);
    });

    test('accepts a session with no longitudinal block', () {
      // Sessions recorded before this layer existed still have to parse.
      final MonitoringSession session =
          MonitoringSession.fromJson(sessionJson(id: 7));

      expect(session.longitudinal, isNull);
    });
  });

  group('SessionResultScreen', () {
    testWidgets('leads with the longitudinal state',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(longitudinalJson()),
      );

      expect(find.text('YOUR MONITORING RESULT'), findsOneWidget);
      expect(find.text('Within your usual range'), findsOneWidget);
      expect(find.text('USUAL'), findsOneWidget);
    });

    testWidgets('shows insufficient history in plain language',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            state: 'insufficient_data',
            usableHistoryCount: 0,
            baselineObservationCount: null,
            baselineConfidence: null,
            isConfident: false,
          ),
        ),
      );

      expect(find.text('Not enough previous data yet'), findsOneWidget);
      expect(find.text('No earlier sessions to compare with yet.'),
          findsOneWidget);
    });

    testWidgets('reports an observed change without clinical language',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            state: 'changed',
            changedFeatures: <String>['mean_inter_tap_interval_ms'],
          ),
        ),
      );

      expect(
        find.text('A change from your usual range was observed'),
        findsOneWidget,
      );
      expect(find.text('CHANGED'), findsOneWidget);
    });

    testWidgets('says an unusable recording was not compared',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            state: 'unreliable',
            usableHistoryCount: 3,
            baselineObservationCount: 3,
            baselineConfidence: 'full',
          ),
        ),
      );

      expect(find.text('This recording could not be compared'), findsOneWidget);
    });

    testWidgets('softens the wording when the baseline is uncertain',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(baselineConfidence: 'reduced', isConfident: false),
        ),
      );

      expect(find.textContaining('less certain'), findsOneWidget);
    });

    testWidgets('shows recorded medication timing as supporting context',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            medicationContext: 'later_after_medication',
            medicationName: 'Levodopa',
            minutesSinceMedication: 150,
            evidenceStrength: 'stronger',
            comparableObservationCount: 4,
            medicationNote:
                'This assessment was recorded approximately 2h 30m after the '
                'reported medication.',
          ),
        ),
      );

      expect(find.text('MEDICATION CONTEXT'), findsOneWidget);
      expect(find.text('LATER AFTER MEDICATION'), findsOneWidget);
      expect(find.text('Levodopa'), findsOneWidget);
      expect(find.text('2h 30m after the reported dose'), findsOneWidget);
      // The longitudinal result still leads: context is added, not promoted.
      expect(find.text('YOUR MONITORING RESULT'), findsOneWidget);
      expect(find.text('Within your usual range'), findsOneWidget);
    });

    testWidgets('says plainly when no medication timing was available',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            usableHistoryCount: 8,
            evidenceStrength: 'moderate',
          ),
        ),
      );

      expect(find.text('TIMING NOT RECORDED'), findsOneWidget);
      expect(
        find.text('Medication timing was not available for this assessment.'),
        findsOneWidget,
      );
      // No elapsed time and no medication name are invented for the gap.
      expect(find.textContaining('after the reported dose'), findsNothing);
      expect(find.textContaining('before the reported dose'), findsNothing);
    });

    testWidgets('never states a clinical conclusion about the medication',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            state: 'changed',
            changedFeatures: <String>['taps_per_second'],
            medicationContext: 'later_after_medication',
            medicationName: 'Levodopa',
            minutesSinceMedication: 150,
            evidenceStrength: 'stronger',
            comparableObservationCount: 4,
            medicationNote:
                'This assessment was recorded approximately 2h 30m after the '
                'reported medication.',
          ),
        ),
      );

      // A change is described; the medication is placed in time, not blamed.
      expect(find.text('A change from your usual range was observed'),
          findsOneWidget);
      for (final String forbidden in <String>[
        'wearing off',
        'not working',
        'worsening',
        'has stopped',
        'effect of your medication',
        'because of your medication',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('describes the evidence without a percentage',
        (WidgetTester tester) async {
      await pumpResult(
        tester,
        LongitudinalSummary.fromJson(
          longitudinalJson(
            evidenceStrength: 'moderate',
            medicationContext: 'unknown',
          ),
        ),
      );

      expect(find.textContaining('rests on your own recorded history'),
          findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('still renders a session with no longitudinal block',
        (WidgetTester tester) async {
      // Backwards compatibility: an older session must still show its result.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SessionResultScreen(
            assessmentTitle: 'Finger Tapping',
            completedAt: DateTime.parse('2026-06-18T10:00:30Z'),
            result: sampleResult(),
            onDone: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOUR MONITORING RESULT'), findsNothing);
      expect(find.text('Session complete'), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing',
        (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SessionResultScreen(
            assessmentTitle: 'Finger Tapping',
            completedAt: DateTime.parse('2026-06-18T10:00:30Z'),
            result: sampleResult(),
            longitudinal: LongitudinalSummary.fromJson(
              longitudinalJson(
                state: 'changed',
                baselineConfidence: 'reduced',
                isConfident: false,
              ),
            ),
            onDone: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('MonitoringHistorySection', () {
    testWidgets('shows the longitudinal state for each session',
        (WidgetTester tester) async {
      await pumpHistory(tester, <Map<String, dynamic>>[
        sessionJson(id: 3, longitudinal: longitudinalJson(state: 'changed')),
        sessionJson(
          id: 2,
          longitudinal: longitudinalJson(
            state: 'insufficient_data',
            usableHistoryCount: 1,
            baselineObservationCount: null,
            baselineConfidence: null,
            isConfident: false,
          ),
        ),
      ]);

      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Building history'), findsOneWidget);
      expect(find.text('Finger Tapping'), findsNWidgets(2));
    });

    testWidgets('omits the chip when a session has no longitudinal state',
        (WidgetTester tester) async {
      await pumpHistory(tester, <Map<String, dynamic>>[sessionJson(id: 3)]);

      expect(find.text('Usual'), findsNothing);
      expect(find.text('Changed'), findsNothing);
    });
  });
}

/// Builds the history section over a real [MonitoringController] whose
/// history endpoint answers with [sessions].
///
/// Uses the same MockClient wiring as the other monitoring tests, so the real
/// repository and JSON parsing are exercised rather than a stubbed controller.
Future<void> pumpHistory(
  WidgetTester tester,
  List<Map<String, dynamic>> sessions,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1200);
  addTearDown(tester.view.reset);

  final SessionTokenCache tokenCache = SessionTokenCache();
  final MonitoringController controller = MonitoringController(
    repository: MonitoringRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient(
          (http.Request request) async =>
              http.Response(jsonEncode(sessions), 200),
        ),
        sessionToken: tokenCache,
      ),
    ),
  );
  await controller.loadHistory();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: MonitoringHistorySection(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}
