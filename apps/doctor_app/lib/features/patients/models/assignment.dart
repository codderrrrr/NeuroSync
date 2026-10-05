/// One exercise the doctor assigned to a patient.
class Assignment {
  const Assignment({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.assessmentSlug,
    required this.assessmentTitle,
    required this.durationSeconds,
    required this.parameters,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      assessmentSlug: json['assessment_slug'] as String,
      assessmentTitle: json['assessment_title'] as String,
      durationSeconds: json['duration_seconds'] as int,
      parameters: <String, Object>{
        ...(json['parameters'] as Map<String, dynamic>? ??
            const <String, dynamic>{}),
      },
    );
  }

  final int id;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Which catalog test this is, so the editor knows what to render.
  final String assessmentSlug;
  final String assessmentTitle;

  /// How long the patient should record for, in seconds.
  final int durationSeconds;

  /// Every setting this exercise uses, resolved against the catalog.
  final Map<String, Object> parameters;

  /// True once a doctor has removed it from the patient.
  ///
  /// The patient no longer sees it, but their recordings against it are kept,
  /// so it stays listed here rather than disappearing from their history.
  bool get isRemoved => status == 'archived';

  bool get wasEdited => updatedAt.isAfter(createdAt);
}
