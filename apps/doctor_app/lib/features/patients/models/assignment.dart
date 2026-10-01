/// One exercise the doctor assigned to a patient.
class Assignment {
  const Assignment({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.assessmentTitle,
    required this.durationSeconds,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      assessmentTitle: json['assessment_title'] as String,
      durationSeconds: json['duration_seconds'] as int,
    );
  }

  final int id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String assessmentTitle;

  /// How long the patient should tap, in seconds.
  final int durationSeconds;
}
