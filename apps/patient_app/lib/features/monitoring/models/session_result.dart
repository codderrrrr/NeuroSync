/// Quality of one recording, as evaluated deterministically by the backend.
///
/// The state describes the recording only - whether the data is usable - and
/// never says anything about the patient.
enum RecordingQuality {
  valid,
  borderline,
  invalid,
  incomplete;

  static RecordingQuality fromApi(String value) {
    switch (value) {
      case 'valid':
        return RecordingQuality.valid;
      case 'borderline':
        return RecordingQuality.borderline;
      case 'invalid':
        return RecordingQuality.invalid;
      case 'incomplete':
        return RecordingQuality.incomplete;
      default:
        throw FormatException('Unknown recording quality: $value');
    }
  }

  /// Patient-facing summary: what happened to the recording, not to the body.
  String get label {
    switch (this) {
      case RecordingQuality.valid:
        return 'Good recording';
      case RecordingQuality.borderline:
        return 'Usable, with some issues';
      case RecordingQuality.invalid:
        return 'Recording could not be used';
      case RecordingQuality.incomplete:
        return 'Ended early';
    }
  }
}

/// The backend's deterministic summary of one recording.
///
/// Every field describes the session - duration, taps, rhythm statistics and
/// quality. Nothing here is a clinical score and nothing here diagnoses.
class SessionResult {
  const SessionResult({
    required this.totalTaps,
    required this.durationMs,
    required this.meanInterTapIntervalMs,
    required this.interTapVariabilityMs,
    required this.longestPauseMs,
    required this.tapsPerSecond,
    required this.quality,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    return SessionResult(
      totalTaps: json['total_taps'] as int,
      durationMs: json['duration_ms'] as int,
      meanInterTapIntervalMs: json['mean_inter_tap_interval_ms'] as int,
      interTapVariabilityMs: json['inter_tap_variability_ms'] as int,
      longestPauseMs: json['longest_pause_ms'] as int,
      tapsPerSecond: (json['taps_per_second'] as num).toDouble(),
      quality: RecordingQuality.fromApi(json['quality'] as String),
    );
  }

  final int totalTaps;
  final int durationMs;
  final int meanInterTapIntervalMs;
  final int interTapVariabilityMs;
  final int longestPauseMs;
  final double tapsPerSecond;
  final RecordingQuality quality;
}
