/// What the patient reported about one dose.
///
/// `notSure` is a real answer, not a missing value: the patient could not
/// recall whether or when they took it. The backend keeps that distinction,
/// and so does this app, so "I don't know" is never silently recorded as
/// "taken".
enum MedicationAdherence {
  taken,
  notTaken,
  notSure;

  static MedicationAdherence fromApi(String value) {
    switch (value) {
      case 'taken':
        return MedicationAdherence.taken;
      case 'not_taken':
        return MedicationAdherence.notTaken;
      case 'not_sure':
        return MedicationAdherence.notSure;
      default:
        throw FormatException('Unknown medication adherence: $value');
    }
  }

  String get apiValue {
    switch (this) {
      case MedicationAdherence.taken:
        return 'taken';
      case MedicationAdherence.notTaken:
        return 'not_taken';
      case MedicationAdherence.notSure:
        return 'not_sure';
    }
  }

  /// Short label for the choice the patient makes.
  String get label {
    switch (this) {
      case MedicationAdherence.taken:
        return 'I took it';
      case MedicationAdherence.notTaken:
        return 'I did not take it';
      case MedicationAdherence.notSure:
        return 'Not sure';
    }
  }
}

/// A medication the patient (or their care team) records.
///
/// Dose and frequency are free text kept exactly as typed. The app never
/// parses them into numbers and never suggests changing them: interpreting a
/// dose is a clinical decision, not an app feature.
class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.doseLabel,
    required this.frequencyLabel,
    required this.isActive,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as int,
      name: json['name'] as String,
      doseLabel: json['dose_label'] as String?,
      frequencyLabel: json['frequency_label'] as String?,
      isActive: json['is_active'] as bool,
    );
  }

  final int id;
  final String name;
  final String? doseLabel;
  final String? frequencyLabel;

  /// Inactive medications stay on record but stop describing the patient's
  /// current regimen, so they cannot supply context for a new assessment.
  final bool isActive;

  /// "Levodopa · 100mg · 4 times daily", skipping whatever was not given.
  String get description {
    final List<String> parts = <String>[name];
    if (doseLabel != null && doseLabel!.isNotEmpty) {
      parts.add(doseLabel!);
    }
    if (frequencyLabel != null && frequencyLabel!.isNotEmpty) {
      parts.add(frequencyLabel!);
    }
    return parts.join(' · ');
  }
}

/// One reported dose, as the backend stored it.
class MedicationEvent {
  const MedicationEvent({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.adherence,
    required this.scheduledAt,
    required this.takenAt,
    required this.recordedAt,
  });

  factory MedicationEvent.fromJson(Map<String, dynamic> json) {
    return MedicationEvent(
      id: json['id'] as int,
      medicationId: json['medication_id'] as int,
      medicationName: json['medication_name'] as String?,
      adherence: MedicationAdherence.fromApi(json['adherence'] as String),
      scheduledAt: json['scheduled_at'] == null
          ? null
          : DateTime.parse(json['scheduled_at'] as String),
      takenAt: json['taken_at'] == null
          ? null
          : DateTime.parse(json['taken_at'] as String),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );
  }

  final int id;
  final int medicationId;
  final String? medicationName;
  final MedicationAdherence adherence;
  final DateTime? scheduledAt;
  final DateTime? takenAt;
  final DateTime recordedAt;

  /// Whether the patient actually reported a time for this dose.
  ///
  /// The backend decides the resulting context; this only reports what the
  /// patient actually told us.
  bool get hasKnownTime =>
      adherence == MedicationAdherence.taken && takenAt != null;
}
