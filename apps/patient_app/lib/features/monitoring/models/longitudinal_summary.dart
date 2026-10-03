import '../../medication/models/medication_context.dart';

/// How one recording compares with the patient's own past recordings.
///
/// A monitoring state the backend derived from this patient's history only.
/// It is not a diagnosis, a severity stage, or a prediction: it says whether
/// the recording looks like the patient's usual range, and how much history
/// that judgement rests on.
enum LongitudinalState {
  insufficientData,
  withinBaseline,
  changed,
  unreliable;

  static LongitudinalState fromApi(String value) {
    switch (value) {
      case 'insufficient_data':
        return LongitudinalState.insufficientData;
      case 'within_baseline':
        return LongitudinalState.withinBaseline;
      case 'changed':
        return LongitudinalState.changed;
      case 'unreliable':
        return LongitudinalState.unreliable;
      default:
        throw FormatException('Unknown longitudinal state: $value');
    }
  }

  /// Plain-language headline. Deliberately about the recording against the
  /// patient's own range, never about their health or a diagnosis.
  String get label {
    switch (this) {
      case LongitudinalState.withinBaseline:
        return 'Within your usual range';
      case LongitudinalState.changed:
        return 'A change from your usual range was observed';
      case LongitudinalState.insufficientData:
        return 'Not enough previous data yet';
      case LongitudinalState.unreliable:
        return 'This recording could not be compared';
    }
  }

  /// One sentence of context under the headline.
  String get explanation {
    switch (this) {
      case LongitudinalState.withinBaseline:
        return 'This recording looks like your recent recordings.';
      case LongitudinalState.changed:
        return 'This recording differs from your recent recordings. '
            'Your doctor can review the difference.';
      case LongitudinalState.insufficientData:
        return 'Keep recording and a comparison will be possible soon.';
      case LongitudinalState.unreliable:
        return 'There was not enough usable data in this recording to compare it.';
    }
  }

  /// A short form for the history list, where space is tight.
  String get shortLabel {
    switch (this) {
      case LongitudinalState.withinBaseline:
        return 'Usual';
      case LongitudinalState.changed:
        return 'Changed';
      case LongitudinalState.insufficientData:
        return 'Building history';
      case LongitudinalState.unreliable:
        return 'Not compared';
    }
  }
}

/// The backend's longitudinal judgement for one session, with its context.
class LongitudinalSummary {
  const LongitudinalSummary({
    required this.state,
    required this.usableHistoryCount,
    required this.baselineObservationCount,
    required this.baselineConfidence,
    required this.changedFeatures,
    required this.isConfident,
    required this.medicationContext,
    required this.medicationName,
    required this.minutesSinceMedication,
    required this.evidenceStrength,
    required this.comparableObservationCount,
    required this.medicationNote,
  });

  factory LongitudinalSummary.fromJson(Map<String, dynamic> json) {
    return LongitudinalSummary(
      state: LongitudinalState.fromApi(json['state'] as String),
      usableHistoryCount: json['usable_history_count'] as int,
      baselineObservationCount: json['baseline_observation_count'] as int?,
      baselineConfidence: json['baseline_confidence'] as String?,
      changedFeatures:
          (json['changed_features'] as List<dynamic>? ?? const <dynamic>[])
              .cast<String>(),
      isConfident: json['is_confident'] as bool,
      medicationContext: MedicationContext.fromApi(
        json['medication_context'] as String?,
      ),
      medicationName: json['medication_name'] as String?,
      minutesSinceMedication: json['minutes_since_medication'] as int?,
      evidenceStrength: EvidenceStrength.fromApi(
        json['evidence_strength'] as String?,
      ),
      comparableObservationCount:
          json['comparable_observation_count'] as int? ?? 0,
      medicationNote: json['medication_note'] as String? ??
          'Medication timing was not available for this assessment.',
    );
  }

  final LongitudinalState state;

  /// Usable previous sessions considered when this state was reached.
  final int usableHistoryCount;

  /// How many sessions the baseline itself rests on; null while building.
  final int? baselineObservationCount;

  /// `full` or `reduced`, or null when there is no baseline yet.
  final String? baselineConfidence;

  /// Which tracked features were outside their tolerance.
  final List<String> changedFeatures;

  /// False when the state rests on a reduced-confidence baseline, so the UI
  /// can soften its wording rather than presenting a weak conclusion as
  /// settled.
  final bool isConfident;

  /// Where the assessment fell relative to the dose the patient reported.
  ///
  /// Supporting context for [state], never an explanation of it: a recording
  /// can differ from the patient's range under any context, and the app never
  /// implies the medication caused the difference.
  final MedicationContext medicationContext;

  /// The medication the patient attached, exactly as they recorded it.
  final String? medicationName;

  /// Minutes between the reported dose and the assessment; null when the
  /// timing is unknown.
  final int? minutesSinceMedication;

  /// How much recorded information stands behind this reading.
  final EvidenceStrength evidenceStrength;

  /// Earlier usable sessions recorded under this same medication context.
  final int comparableObservationCount;

  /// A cautious sentence describing the timing, written by the backend so the
  /// app and the server never word the same fact differently.
  final String medicationNote;

  /// Supporting line describing how much history this rests on.
  String get historyContext {
    final int count = baselineObservationCount ?? usableHistoryCount;
    if (count == 0) {
      return 'No earlier sessions to compare with yet.';
    }
    final String sessions =
        count == 1 ? '1 earlier session' : '$count earlier sessions';
    return 'Compared with $sessions of your own recordings.';
  }

  /// Extra reassurance when the comparison is weakly supported.
  String? get confidenceNote {
    if (baselineConfidence == 'reduced') {
      return 'Some earlier recordings were uneven, so this comparison is less '
          'certain.';
    }
    return null;
  }

  /// The elapsed time the way a person would say it, or null when unknown.
  String? get timingLabel {
    final int? minutes = minutesSinceMedication;
    if (!medicationContext.isKnown || minutes == null) {
      return null;
    }
    if (medicationContext == MedicationContext.beforeMedication) {
      return '${_humanise(minutes)} before the reported dose';
    }
    return '${_humanise(minutes)} after the reported dose';
  }

  static String _humanise(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}
