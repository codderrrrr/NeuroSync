/// A NeuroSync assessment, as defined by the backend catalog.
///
/// The patient app never decides which tests exist: it renders what the API
/// returns. An assessment with `isSupported == false` has no runner yet and is
/// shown as "Not available yet"; it can never be launched.
class Assessment {
  const Assessment({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.instructions,
    required this.executionType,
    required this.defaultDurationSeconds,
    required this.isSupported,
    required this.parameters,
  });

  factory Assessment.fromJson(Map<String, dynamic> json) {
    return Assessment(
      id: json['id'] as int,
      slug: json['slug'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      instructions: json['instructions'] as String,
      executionType: json['execution_type'] as String,
      defaultDurationSeconds: json['default_duration_seconds'] as int,
      isSupported: json['is_supported'] as bool,
      parameters: (json['parameters'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(AssessmentSetting.fromJson)
          .toList(growable: false),
    );
  }

  final int id;
  final String slug;
  final String title;
  final String description;
  final String instructions;
  final String executionType;
  final int defaultDurationSeconds;
  final bool isSupported;

  /// What a doctor may change about this test, and what it defaults to.
  ///
  /// The patient never chooses any of it; they are shown the values their own
  /// plan carries so the test they are about to do is not a surprise.
  final List<AssessmentSetting> parameters;

  /// Whether the app has a runner for this assessment.
  ///
  /// The client mirrors the server flag so an assessment can never be launched
  /// without a runner, even if the plan data were stale.
  bool get isExecutable =>
      isSupported &&
      (executionType == 'tap_task' || executionType == 'canvas_task');

  bool get isCanvas => executionType == 'canvas_task';

  /// Label for unavailable assessments.
  String get availabilityLabel =>
      isSupported ? 'Available' : 'Not available yet';
}

/// One declared setting of a test, so the patient can see how their doctor
/// configured it before they start.
class AssessmentSetting {
  const AssessmentSetting({
    required this.key,
    required this.label,
    required this.kind,
    required this.defaultValue,
    this.choices = const <String>[],
  });

  factory AssessmentSetting.fromJson(Map<String, dynamic> json) =>
      AssessmentSetting(
        key: json['key'] as String,
        label: json['label'] as String,
        kind: json['kind'] as String,
        defaultValue: json['default'] as Object,
        choices: (json['choices'] as List<dynamic>? ?? const <dynamic>[])
            .cast<String>(),
      );

  final String key;
  final String label;
  final String kind;
  final Object defaultValue;
  final List<String> choices;

  /// A plain-language rendering of one value, for the "your test is set up as"
  /// list. Unknown keys are skipped by the caller rather than shown raw, so a
  /// setting this app does not recognise never appears as a bare identifier.
  String describe(Object value) {
    if (kind == 'choice' && value is String) {
      switch (value) {
        case 'left':
          return 'Left hand';
        case 'right':
          return 'Right hand';
        case 'slow':
          return 'Slow';
        case 'comfortable':
          return 'Comfortable speed';
        case 'fast':
          return 'Fast';
        default:
          return _capitalise(value);
      }
    }
    switch (key) {
      case 'repetitions':
        return '$value time${value == 1 ? '' : 's'}';
      case 'turns':
        return '$value turn${value == 1 ? '' : 's'}';
      case 'size_percent':
      case 'line_length_percent':
        return '$value% of the screen';
      case 'phrase':
        return '"$value"';
      default:
        return _capitalise('$value');
    }
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
