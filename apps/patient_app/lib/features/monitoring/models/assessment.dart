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

  /// Whether the app has a runner for this assessment.
  ///
  /// The client mirrors the server flag so an assessment can never be launched
  /// without a runner, even if the plan data were stale.
  bool get isExecutable => isSupported && executionType == 'tap_task';

  /// Label for unavailable assessments.
  String get availabilityLabel =>
      isSupported ? 'Available' : 'Not available yet';
}
