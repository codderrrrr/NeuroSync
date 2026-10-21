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

  /// A short form for a pill beside other words.
  ///
  /// The full phrase needs a line to itself. Beside a title it squeezes the
  /// title out of the row, and a title cut short is a title the patient
  /// cannot read.
  String get shortLabel {
    switch (this) {
      case RecordingQuality.valid:
        return 'STEADY';
      case RecordingQuality.borderline:
        return 'UNEVEN';
      case RecordingQuality.invalid:
        return 'UNUSABLE';
      case RecordingQuality.incomplete:
        return 'EARLY';
    }
  }
}

/// The backend's deterministic summary of one recording.
///
/// The backend fills exactly one of [taps] and [canvas], matching the runner
/// that captured the session, so the app reads the block its assessment
/// produces rather than guessing from which fields happen to be set. Every
/// field describes the recording. Nothing here is a clinical score and nothing
/// here diagnoses.
class SessionResult {
  const SessionResult({
    required this.quality,
    this.taps,
    this.canvas,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? taps = json['taps'] as Map<String, dynamic>?;
    final Map<String, dynamic>? canvas =
        json['canvas'] as Map<String, dynamic>?;
    if (taps == null && canvas == null) {
      throw const FormatException(
        'The recording result carries no recognisable features.',
      );
    }
    return SessionResult(
      quality: RecordingQuality.fromApi(json['quality'] as String),
      taps: taps == null ? null : TapResult.fromJson(taps),
      canvas: canvas == null ? null : CanvasResult.fromJson(canvas),
    );
  }

  final RecordingQuality quality;
  final TapResult? taps;
  final CanvasResult? canvas;

  /// How long the recording ran, whichever runner produced it.
  int get durationMs => taps?.durationMs ?? canvas?.durationMs ?? 0;

  /// How much the patient actually did, in their own terms.
  int get movementCount => taps?.totalTaps ?? canvas?.strokeCount ?? 0;

  /// The longest gap with nothing happening, whichever runner produced it.
  int get longestPauseMs => taps?.longestPauseMs ?? canvas?.longestPauseMs ?? 0;

  String get movementLabel => taps != null ? 'taps' : 'passes';
}

/// One finger-tapping recording.
class TapResult {
  const TapResult({
    required this.totalTaps,
    required this.durationMs,
    required this.meanInterTapIntervalMs,
    required this.interTapVariabilityMs,
    required this.longestPauseMs,
    required this.tapsPerSecond,
  });

  factory TapResult.fromJson(Map<String, dynamic> json) => TapResult(
        totalTaps: json['total_taps'] as int,
        durationMs: json['duration_ms'] as int,
        meanInterTapIntervalMs: json['mean_inter_tap_interval_ms'] as int,
        interTapVariabilityMs: json['inter_tap_variability_ms'] as int,
        longestPauseMs: json['longest_pause_ms'] as int,
        tapsPerSecond: (json['taps_per_second'] as num).toDouble(),
      );

  final int totalTaps;
  final int durationMs;
  final int meanInterTapIntervalMs;
  final int interTapVariabilityMs;
  final int longestPauseMs;
  final double tapsPerSecond;
}

/// One canvas (tracing) recording.
///
/// Path length and speed are in the device's own pixels, which is what makes
/// this patient's recordings comparable with their own others and with nothing
/// else.
class CanvasResult {
  const CanvasResult({
    required this.totalPoints,
    required this.strokeCount,
    required this.durationMs,
    required this.longestPauseMs,
    required this.pathLength,
    required this.meanSpeedPxPerSecond,
    required this.peakSpeedPxPerSecond,
    required this.pathEfficiency,
  });

  factory CanvasResult.fromJson(Map<String, dynamic> json) => CanvasResult(
        totalPoints: json['total_points'] as int,
        strokeCount: json['stroke_count'] as int,
        durationMs: json['duration_ms'] as int,
        longestPauseMs: json['longest_pause_ms'] as int,
        pathLength: (json['path_length'] as num).toDouble(),
        meanSpeedPxPerSecond:
            (json['mean_speed_px_per_second'] as num).toDouble(),
        peakSpeedPxPerSecond:
            (json['peak_speed_px_per_second'] as num).toDouble(),
        pathEfficiency: (json['path_efficiency'] as num).toDouble(),
      );

  final int totalPoints;
  final int strokeCount;
  final int durationMs;
  final int longestPauseMs;
  final double pathLength;
  final double meanSpeedPxPerSecond;
  final double peakSpeedPxPerSecond;

  /// 1.0 is a direct path from start to finish; larger means the finger
  /// travelled further to get there.
  final double pathEfficiency;
}
