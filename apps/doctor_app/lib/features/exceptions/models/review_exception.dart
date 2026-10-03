/// One observation the monitoring pipeline routed for a specialist to look at.
///
/// A routing record, not a finding. Nothing here says what is wrong with anyone:
/// it says the recording met a configured rule and a clinician has not looked at
/// it yet. `rationale` is the rule's own sentence, kept so the queue can answer
/// "why is this here?" without re-deriving the decision.
class ReviewExceptionSummary {
  const ReviewExceptionSummary({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.exceptionType,
    required this.status,
    required this.rationale,
    required this.createdAt,
    required this.longitudinalState,
    required this.evidenceStrength,
    required this.assessmentTitle,
    required this.medicationContext,
    required this.minutesSinceMedication,
  });

  factory ReviewExceptionSummary.fromJson(Map<String, dynamic> json) {
    return ReviewExceptionSummary(
      id: json['id'] as int,
      patientId: json['patient_id'] as int,
      patientName: json['patient_name'] as String,
      exceptionType: json['exception_type'] as String,
      status: json['status'] as String,
      rationale: json['rationale'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      longitudinalState: json['longitudinal_state'] as String,
      evidenceStrength: json['evidence_strength'] as String,
      assessmentTitle: json['assessment_title'] as String,
      medicationContext: json['medication_context'] as String,
      minutesSinceMedication: json['minutes_since_medication'] as int?,
    );
  }

  final int id;
  final int patientId;
  final String patientName;

  /// Why it was routed: persistent, contextual, or a single supported change.
  final String exceptionType;

  /// `open`, `reviewed` or `dismissed`.
  final String status;

  final String rationale;
  final DateTime createdAt;
  final String longitudinalState;

  /// How much supporting information was recorded, never a probability.
  final String evidenceStrength;

  final String assessmentTitle;
  final String medicationContext;
  final int? minutesSinceMedication;

  bool get isOpen => status == 'open';
  bool get isClosed => !isOpen;
}

/// The patient's own reference the observation was compared against.
///
/// Null when no baseline existed yet, which is itself information: there was
/// nothing established to judge the recording by.
class ExceptionBaseline {
  const ExceptionBaseline({
    required this.observationCount,
    required this.confidence,
    required this.tapsPerSecond,
    required this.meanInterTapIntervalMs,
    required this.interTapVariabilityMs,
    required this.longestPauseMs,
  });

  factory ExceptionBaseline.fromJson(Map<String, dynamic> json) {
    return ExceptionBaseline(
      observationCount: json['observation_count'] as int,
      confidence: json['confidence'] as String,
      tapsPerSecond: (json['taps_per_second'] as num).toDouble(),
      meanInterTapIntervalMs: json['mean_inter_tap_interval_ms'] as int,
      interTapVariabilityMs: json['inter_tap_variability_ms'] as int,
      longestPauseMs: json['longest_pause_ms'] as int,
    );
  }

  final int observationCount;
  final String confidence;
  final double tapsPerSecond;
  final int meanInterTapIntervalMs;
  final int interTapVariabilityMs;
  final int longestPauseMs;
}

/// One exception with the recording and reference behind the decision.
///
/// The queue row is a triage view; this is the evidence a review actually turns
/// on, so it is fetched only once an entry has been opened.
class ReviewExceptionDetail {
  const ReviewExceptionDetail({
    required this.summary,
    required this.routingRule,
    required this.supportingObservations,
    required this.longitudinalResultId,
    required this.monitoringSessionId,
    required this.usableHistoryCount,
    required this.baselineConfidence,
    required this.changedFeatures,
    required this.recordingQuality,
    required this.totalTaps,
    required this.durationMs,
    required this.tapsPerSecond,
    required this.meanInterTapIntervalMs,
    required this.interTapVariabilityMs,
    required this.longestPauseMs,
    required this.baseline,
    required this.reviewedByDoctorId,
    required this.reviewedAt,
    required this.reviewNote,
  });

  factory ReviewExceptionDetail.fromJson(Map<String, dynamic> json) {
    final Object? baseline = json['baseline'];
    return ReviewExceptionDetail(
      summary: ReviewExceptionSummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      routingRule: json['routing_rule'] as String,
      supportingObservations: json['supporting_observations'] as int,
      longitudinalResultId: json['longitudinal_result_id'] as int,
      monitoringSessionId: json['monitoring_session_id'] as int,
      usableHistoryCount: json['usable_history_count'] as int,
      baselineConfidence: json['baseline_confidence'] as String?,
      changedFeatures:
          (json['changed_features'] as List<dynamic>?)?.cast<String>() ??
              const <String>[],
      recordingQuality: json['recording_quality'] as String,
      totalTaps: json['total_taps'] as int,
      durationMs: json['duration_ms'] as int,
      tapsPerSecond: (json['taps_per_second'] as num).toDouble(),
      meanInterTapIntervalMs: json['mean_inter_tap_interval_ms'] as int,
      interTapVariabilityMs: json['inter_tap_variability_ms'] as int,
      longestPauseMs: json['longest_pause_ms'] as int,
      baseline: baseline is Map<String, dynamic>
          ? ExceptionBaseline.fromJson(baseline)
          : null,
      reviewedByDoctorId: json['reviewed_by_doctor_id'] as int?,
      reviewedAt: json['reviewed_at'] == null
          ? null
          : DateTime.parse(json['reviewed_at'] as String),
      reviewNote: json['review_note'] as String?,
    );
  }

  final ReviewExceptionSummary summary;
  final String routingRule;

  /// The count that justified the decision: consecutive changes, or matching
  /// observations under one medication context.
  final int supportingObservations;

  final int longitudinalResultId;
  final int monitoringSessionId;
  final int usableHistoryCount;
  final String? baselineConfidence;

  /// Which tracked features fell outside their tolerance.
  final List<String> changedFeatures;

  final String recordingQuality;
  final int totalTaps;
  final int durationMs;
  final double tapsPerSecond;
  final int meanInterTapIntervalMs;
  final int interTapVariabilityMs;
  final int longestPauseMs;
  final ExceptionBaseline? baseline;

  final int? reviewedByDoctorId;
  final DateTime? reviewedAt;

  /// The reviewing doctor's own words. The app never writes one.
  final String? reviewNote;

  bool get isOpen => summary.isOpen;
}

/// The two ways a clinician can close an exception.
///
/// `open` is deliberately absent: it is the state an exception arrives in, not
/// an outcome a reviewer picks.
enum ReviewOutcome {
  reviewed('reviewed'),
  dismissed('dismissed');

  const ReviewOutcome(this.wire);

  final String wire;
}

/// Which slice of the queue is on screen.
enum ExceptionFilter {
  all('all', 'All'),
  open('open', 'Open'),
  reviewed('reviewed', 'Reviewed'),
  dismissed('dismissed', 'Dismissed');

  const ExceptionFilter(this.wire, this.label);

  final String wire;

  /// The caption on the filter control.
  final String label;

  /// The API filters by status only, so "all" sends nothing rather than a
  /// status that would match nothing.
  String? get statusQuery => wire == 'all' ? null : wire;
}

/// A short, human name for each routing reason.
///
/// The wire values are terse and lowercase; a clinician should never have to
/// decode `context_corroborated_change` on a screen.
String exceptionTypeLabel(String exceptionType) {
  switch (exceptionType) {
    case 'persistent_change':
      return 'Repeated change';
    case 'contextual_change':
      return 'Change under a known context';
    case 'review_requested':
      return 'Single change';
    default:
      return 'Routed for review';
  }
}

/// Human labels for the evidence levels, which describe how much was recorded.
String evidenceLabel(String evidenceStrength) {
  switch (evidenceStrength) {
    case 'stronger':
      return 'Strong evidence';
    case 'moderate':
      return 'Moderate evidence';
    case 'limited':
      return 'Limited evidence';
    default:
      return 'Insufficient evidence';
  }
}

/// Human labels for medication timing context.
String medicationContextLabel(String context) {
  switch (context) {
    case 'recently_after_medication':
      return 'Shortly after a dose';
    case 'later_after_medication':
      return 'Later after a dose';
    case 'before_medication':
      return 'Before a dose';
    default:
      // Never narrowed into a window the patient did not report.
      return 'Medication timing not reported';
  }
}

/// The tracked features a comparison can report, with readable names.
const Map<String, String> kChangedFeatureLabels = <String, String>{
  'taps_per_second': 'Tap rate',
  'mean_inter_tap_interval_ms': 'Average gap between taps',
  'inter_tap_variability_ms': 'Variability between taps',
  'longest_pause_ms': 'Longest pause',
};

String changedFeatureLabel(String key) => kChangedFeatureLabels[key] ?? key;
