import 'assessment.dart';
import 'session_result.dart';

/// One execution of a monitoring assessment.
class MonitoringSession {
  const MonitoringSession({
    required this.id,
    required this.status,
    required this.assessment,
    required this.startedAt,
    required this.completedAt,
    required this.result,
  });

  factory MonitoringSession.fromJson(Map<String, dynamic> json) {
    return MonitoringSession(
      id: json['id'] as int,
      status: json['status'] as String,
      assessment:
          Assessment.fromJson(json['assessment'] as Map<String, dynamic>),
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      result: json['result'] == null
          ? null
          : SessionResult.fromJson(json['result'] as Map<String, dynamic>),
    );
  }

  final int id;
  final String status;
  final Assessment assessment;
  final DateTime startedAt;
  final DateTime? completedAt;
  final SessionResult? result;

  bool get isCompleted => status == 'completed';
}
