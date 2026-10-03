import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/medication/models/medication.dart';
import 'package:neurosync_patient/features/medication/models/medication_context.dart';

Map<String, dynamic> medicationJson({
  String name = 'Levodopa',
  String? doseLabel = '100mg',
  String? frequencyLabel = '4 times daily',
  bool isActive = true,
}) {
  return <String, dynamic>{
    'id': 1,
    'name': name,
    'dose_label': doseLabel,
    'frequency_label': frequencyLabel,
    'is_active': isActive,
    'created_at': '2026-06-18T10:00:00Z',
    'updated_at': '2026-06-18T10:00:00Z',
  };
}

Map<String, dynamic> eventJson({
  String adherence = 'taken',
  String? takenAt = '2026-06-18T09:30:00Z',
  String? scheduledAt,
  String? medicationName = 'Levodopa',
}) {
  return <String, dynamic>{
    'id': 7,
    'medication_id': 1,
    'medication_name': medicationName,
    'adherence': adherence,
    'scheduled_at': scheduledAt,
    'taken_at': takenAt,
    'recorded_at': '2026-06-18T10:00:00Z',
  };
}

void main() {
  group('MedicationAdherence', () {
    test('round-trips the API vocabulary', () {
      expect(MedicationAdherence.fromApi('taken'), MedicationAdherence.taken);
      expect(
        MedicationAdherence.fromApi('not_taken'),
        MedicationAdherence.notTaken,
      );
      expect(
        MedicationAdherence.fromApi('not_sure'),
        MedicationAdherence.notSure,
      );
      for (final MedicationAdherence value in MedicationAdherence.values) {
        expect(MedicationAdherence.fromApi(value.apiValue), value);
      }
    });

    test('an unrecognised value is refused rather than guessed at', () {
      expect(
        () => MedicationAdherence.fromApi('maybe'),
        throwsFormatException,
      );
    });

    test('"not sure" is a real answer, not a missing value', () {
      // The distinction matters: the backend treats not_sure as unknown timing
      // even if a timestamp happens to be attached.
      expect(MedicationAdherence.notSure.label, 'Not sure');
      expect(MedicationAdherence.notSure, isNot(MedicationAdherence.notTaken));
    });
  });

  group('Medication', () {
    test('parses the fields the API returns', () {
      final Medication medication = Medication.fromJson(medicationJson());

      expect(medication.id, 1);
      expect(medication.name, 'Levodopa');
      expect(medication.doseLabel, '100mg');
      expect(medication.frequencyLabel, '4 times daily');
      expect(medication.isActive, isTrue);
    });

    test('describes itself with whatever was actually given', () {
      expect(Medication.fromJson(medicationJson()).description,
          'Levodopa · 100mg · 4 times daily');
      expect(
        Medication.fromJson(
          medicationJson(doseLabel: null, frequencyLabel: null),
        ).description,
        'Levodopa',
      );
    });

    test('a null dose label does not become the word "null"', () {
      final String description = Medication.fromJson(
        medicationJson(doseLabel: null, frequencyLabel: 'morning'),
      ).description;

      expect(description, 'Levodopa · morning');
      expect(description, isNot(contains('null')));
    });

    test('an inactive medication is preserved as recorded', () {
      final Medication medication =
          Medication.fromJson(medicationJson(isActive: false));

      expect(medication.isActive, isFalse);
    });
  });

  group('MedicationEvent', () {
    test('parses a dose with a known time', () {
      final MedicationEvent event = MedicationEvent.fromJson(eventJson());

      expect(event.id, 7);
      expect(event.medicationId, 1);
      expect(event.medicationName, 'Levodopa');
      expect(event.adherence, MedicationAdherence.taken);
      expect(event.takenAt, DateTime.parse('2026-06-18T09:30:00Z'));
      expect(event.scheduledAt, isNull);
      expect(event.hasKnownTime, isTrue);
    });

    test('a dose with no time is still a complete report', () {
      final MedicationEvent event =
          MedicationEvent.fromJson(eventJson(takenAt: null));

      expect(event.adherence, MedicationAdherence.taken);
      expect(event.takenAt, isNull);
      expect(event.hasKnownTime, isFalse);
    });

    test('"not sure" with a time attached is still not a known time', () {
      // The patient said they could not recall. A stray timestamp must not
      // upgrade that answer into certainty on the phone.
      final MedicationEvent event = MedicationEvent.fromJson(
        eventJson(adherence: 'not_sure'),
      );

      expect(event.takenAt, isNotNull);
      expect(event.hasKnownTime, isFalse);
    });

    test('a dose with no medication name still parses', () {
      final MedicationEvent event =
          MedicationEvent.fromJson(eventJson(medicationName: null));

      expect(event.medicationName, isNull);
    });
  });

  group('MedicationContext', () {
    test('maps every backend value', () {
      expect(
        MedicationContext.fromApi('before_medication'),
        MedicationContext.beforeMedication,
      );
      expect(
        MedicationContext.fromApi('recently_after_medication'),
        MedicationContext.recentlyAfterMedication,
      );
      expect(
        MedicationContext.fromApi('later_after_medication'),
        MedicationContext.laterAfterMedication,
      );
      expect(MedicationContext.fromApi('unknown'), MedicationContext.unknown);
    });

    test('a payload with no context at all reads as unknown', () {
      // A session recorded before this layer existed. Same statement: nothing
      // was reported, so nothing is claimed.
      expect(MedicationContext.fromApi(null), MedicationContext.unknown);
    });

    test('an unrecognised value is refused rather than guessed at', () {
      expect(
        () => MedicationContext.fromApi('wearing_off'),
        throwsFormatException,
      );
    });

    test('only a known context claims timing', () {
      expect(MedicationContext.unknown.isKnown, isFalse);
      for (final MedicationContext context in MedicationContext.values) {
        if (context != MedicationContext.unknown) {
          expect(context.isKnown, isTrue);
        }
      }
    });

    test('no label makes a clinical claim', () {
      for (final MedicationContext context in MedicationContext.values) {
        final String label = context.label.toLowerCase();
        expect(label, isNot(contains('wearing')));
        expect(label, isNot(contains('effective')));
        expect(label, isNot(contains('working')));
        expect(label, isNot(contains('worsen')));
      }
    });
  });

  group('EvidenceStrength', () {
    test('maps every backend value, and a missing one to insufficient', () {
      expect(
        EvidenceStrength.fromApi('insufficient'),
        EvidenceStrength.insufficient,
      );
      expect(EvidenceStrength.fromApi('limited'), EvidenceStrength.limited);
      expect(EvidenceStrength.fromApi('moderate'), EvidenceStrength.moderate);
      expect(EvidenceStrength.fromApi('stronger'), EvidenceStrength.stronger);
      expect(EvidenceStrength.fromApi(null), EvidenceStrength.insufficient);
    });

    test('never renders as a percentage', () {
      for (final EvidenceStrength strength in EvidenceStrength.values) {
        expect(strength.explanation, isNot(matches(RegExp(r'\d+%'))));
        expect(strength.explanation, isNot(contains('%')));
      }
    });

    test('only the strongest level is described as medication-aware', () {
      expect(EvidenceStrength.stronger.isMedicationAware, isTrue);
      for (final EvidenceStrength strength in EvidenceStrength.values) {
        if (strength != EvidenceStrength.stronger) {
          expect(strength.isMedicationAware, isFalse);
        }
      }
    });
  });

  group('DoseTimingChoice', () {
    test('offers a way to say "I do not know"', () {
      // Required: the patient must be able to decline without lying.
      expect(DoseTimingChoice.options.any((DoseTimingChoice c) => c.isUnknown),
          isTrue);
    });

    test('every non-unknown option is a real minute count', () {
      for (final DoseTimingChoice choice in DoseTimingChoice.options) {
        if (choice.isUnknown) {
          continue;
        }
        expect(choice.minutesAgo, isNotNull);
        expect(choice.minutesAgo, greaterThanOrEqualTo(0));
      }
    });

    test('offers no over-precise option', () {
      // A picker precise to the minute invites a number the patient invented.
      for (final DoseTimingChoice choice in DoseTimingChoice.options) {
        final int? minutes = choice.minutesAgo;
        if (minutes == null) {
          continue;
        }
        expect(minutes % 15, 0);
      }
    });
  });
}
