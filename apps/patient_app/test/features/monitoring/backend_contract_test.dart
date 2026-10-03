import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/medication/models/medication.dart';
import 'package:neurosync_patient/features/medication/models/medication_context.dart';
import 'package:neurosync_patient/features/monitoring/models/longitudinal_summary.dart';
import 'package:neurosync_patient/features/monitoring/models/monitoring_session.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';

/// Loads a payload captured verbatim from a running backend.
///
/// The other monitoring tests build their JSON by hand, which proves the parser
/// handles what we *believe* the API returns. These fixtures were recorded from
/// the real application, so they fail if the two halves of the contract ever
/// drift apart.
dynamic _fixture(String name) {
  final File file = File('test/features/monitoring/fixtures/$name.json');
  expect(file.existsSync(), isTrue, reason: 'missing fixture $name.json');
  return jsonDecode(file.readAsStringSync());
}

Map<String, dynamic> _fixtureObject(String name) =>
    _fixture(name) as Map<String, dynamic>;

List<dynamic> _fixtureList(String name) => _fixture(name) as List<dynamic>;

void main() {
  group('real backend payloads', () {
    test('a completed session parses, including its longitudinal block', () {
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_within_baseline'),
      );

      expect(session.id, 4);
      expect(session.isCompleted, isTrue);
      expect(session.result?.quality, RecordingQuality.valid);
      expect(session.result?.totalTaps, 30);
      expect(session.result?.tapsPerSecond, closeTo(1.034, 0.0001));

      final LongitudinalSummary? summary = session.longitudinal;
      expect(summary, isNotNull);
      expect(summary!.state, LongitudinalState.withinBaseline);
      expect(summary.usableHistoryCount, 3);
      expect(summary.baselineObservationCount, 3);
      expect(summary.baselineConfidence, 'full');
      expect(summary.changedFeatures, isEmpty);
      expect(summary.isConfident, isTrue);
    });

    test('a zero-valued feature from the backend parses cleanly', () {
      // A perfectly uniform recording really does yield zero variability. The
      // app must render that without crashing or hiding the row.
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_within_baseline'),
      );

      expect(session.result?.interTapVariabilityMs, 0);
    });

    test('the history page parses every session it returns', () {
      final List<dynamic> sessions = _fixtureList('history_page');

      expect(sessions, isNotEmpty);
      final List<MonitoringSession> parsed = sessions
          .cast<Map<String, dynamic>>()
          .map(MonitoringSession.fromJson)
          .toList();

      // Newest first: the only compared session leads the page.
      expect(
          parsed.first.longitudinal?.state, LongitudinalState.withinBaseline);
      for (final MonitoringSession session in parsed) {
        expect(session.longitudinal, isNotNull);
        expect(session.result, isNotNull);
      }
      // Sessions recorded before a baseline existed still carry a state.
      expect(
        parsed.skip(1).every(
              (MonitoringSession s) =>
                  s.longitudinal!.state == LongitudinalState.insufficientData,
            ),
        isTrue,
      );
    });

    test('a session with a known context parses every medication field', () {
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_later_after_medication'),
      );

      final LongitudinalSummary summary = session.longitudinal!;
      expect(
        summary.medicationContext,
        MedicationContext.laterAfterMedication,
      );
      expect(summary.medicationName, 'Levodopa');
      expect(summary.minutesSinceMedication, 150);
      expect(summary.evidenceStrength, EvidenceStrength.stronger);
      expect(summary.comparableObservationCount, 4);
      expect(
        summary.medicationNote,
        'This assessment was recorded approximately 2h 30m after the reported '
        'medication.',
      );
      // The context never displaces the patient's own baseline.
      expect(summary.state, LongitudinalState.withinBaseline);
      expect(summary.usableHistoryCount, 11);
    });

    test('a session whose dose was never dated keeps its event but no window',
        () {
      // The patient said they took it and could not say when. The backend
      // keeps the association and refuses to invent a context.
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_undated_dose'),
      );

      final LongitudinalSummary summary = session.longitudinal!;
      expect(summary.medicationContext, MedicationContext.unknown);
      expect(summary.minutesSinceMedication, isNull);
      expect(summary.timingLabel, isNull);
      // The medication is still named: "they told us, we cannot date it".
      expect(summary.medicationName, 'Levodopa');
      expect(
        summary.medicationNote,
        'Medication timing was not available for this assessment.',
      );
    });

    test('a session with no dose at all reads as unknown everywhere', () {
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_unknown_context'),
      );

      final LongitudinalSummary summary = session.longitudinal!;
      expect(summary.medicationContext, MedicationContext.unknown);
      expect(summary.medicationName, isNull);
      expect(summary.minutesSinceMedication, isNull);
      expect(summary.comparableObservationCount, 0);
      // Plenty of history, but never presented as medication-aware evidence.
      expect(summary.evidenceStrength, EvidenceStrength.moderate);
      expect(summary.evidenceStrength.isMedicationAware, isFalse);
    });

    test('a first known-context session is supported but not corroborated', () {
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_recently_after_medication'),
      );

      final LongitudinalSummary summary = session.longitudinal!;
      expect(
        summary.medicationContext,
        MedicationContext.recentlyAfterMedication,
      );
      expect(summary.minutesSinceMedication, 30);
      expect(summary.comparableObservationCount, 0);
      expect(summary.evidenceStrength, EvidenceStrength.limited);
    });

    test('a change with context is reported as a change, not an explanation',
        () {
      final MonitoringSession session = MonitoringSession.fromJson(
        _fixtureObject('session_changed_with_context'),
      );

      final LongitudinalSummary summary = session.longitudinal!;
      expect(summary.state, LongitudinalState.changed);
      expect(summary.changedFeatures, isNotEmpty);
      expect(summary.medicationContext, MedicationContext.laterAfterMedication);
      expect(summary.minutesSinceMedication, 75);
      // Having the context does not turn the difference into a cause.
      expect(summary.state.label.toLowerCase(), isNot(contains('medication')));
    });

    test('every evidence level the backend can send parses', () {
      final Set<String> levels = <String>{
        for (final String name in <String>[
          'session_recently_after_medication',
          'session_later_after_medication',
          'session_unknown_context',
        ])
          (MonitoringSession.fromJson(_fixtureObject(name))
                  .longitudinal!
                  .evidenceStrength)
              .name,
      };

      expect(
        levels,
        <String>{'limited', 'moderate', 'stronger'},
      );
    });

    test('the medication list payload parses verbatim', () {
      final List<Medication> medications = _fixtureList('medication_list')
          .cast<Map<String, dynamic>>()
          .map(Medication.fromJson)
          .toList();

      expect(medications, hasLength(1));
      expect(medications.single.name, 'Levodopa');
      expect(medications.single.doseLabel, '100mg');
      expect(medications.single.frequencyLabel, '4 times daily');
      expect(medications.single.isActive, isTrue);
    });

    test('the dose-event list payload parses, including an undated dose', () {
      final List<MedicationEvent> events = _fixtureList('medication_events')
          .cast<Map<String, dynamic>>()
          .map(MedicationEvent.fromJson)
          .toList();

      expect(events, isNotEmpty);
      expect(
          events.every((MedicationEvent e) => e.medicationName == 'Levodopa'),
          isTrue);
      // The very first event was recorded without a time, and stayed that way.
      expect(events.last.hasKnownTime, isFalse);
      expect(events.last.takenAt, isNull);
      // Every other event carries the time the patient reported. Newest first,
      // so the undated report is the final entry.
      expect(
        events
            .take(events.length - 1)
            .every((MedicationEvent e) => e.hasKnownTime),
        isTrue,
      );
    });

    test('no medication context the app can render is a clinical claim', () {
      final List<MonitoringSession> sessions = <MonitoringSession>[
        for (final String name in <String>[
          'session_recently_after_medication',
          'session_later_after_medication',
          'session_unknown_context',
          'session_changed_with_context',
          'session_undated_dose',
        ])
          MonitoringSession.fromJson(_fixtureObject(name)),
      ];

      for (final MonitoringSession session in sessions) {
        final LongitudinalSummary summary = session.longitudinal!;
        final String rendered =
            '${summary.medicationContext.label} ${summary.medicationNote} '
                    '${summary.timingLabel ?? ''} '
                    '${summary.evidenceStrength.explanation} ${summary.state.label}'
                .toLowerCase();
        for (final String forbidden in <String>[
          'wearing off',
          'not working',
          'stopped working',
          'worsen',
          'deteriorat',
          'diagnos',
          'stage',
        ]) {
          expect(
            rendered.contains(forbidden),
            isFalse,
            reason: '${session.id}: $forbidden',
          );
        }
      }
    });
  });
}
