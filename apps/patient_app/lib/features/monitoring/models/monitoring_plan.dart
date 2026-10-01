import 'assessment.dart';

/// The patient's active monitoring plan with its ordered assessment items.
///
/// Received entirely from the API: the app decides nothing about which tests
/// exist or in what order they should appear.
class MonitoringPlanItem {
  const MonitoringPlanItem({
    required this.id,
    required this.assessment,
    required this.position,
    required this.completedToday,
    this.durationSeconds,
  });

  factory MonitoringPlanItem.fromJson(Map<String, dynamic> json) {
    return MonitoringPlanItem(
      id: json['id'] as int,
      assessment:
          Assessment.fromJson(json['assessment'] as Map<String, dynamic>),
      position: json['position'] as int,
      completedToday: json['completed_today'] as int,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
    );
  }

  final int id;
  final Assessment assessment;
  final int position;

  /// How many times this item was completed today (server's UTC day).
  final int completedToday;

  /// Doctor-configured duration for this run, in seconds.
  ///
  /// Null when the plan item does not override the assessment default.
  final int? durationSeconds;

  /// The duration a runner should use for this item.
  int get effectiveDurationSeconds =>
      durationSeconds ?? assessment.defaultDurationSeconds;

  bool get isDoneToday => completedToday > 0;
}

class MonitoringPlan {
  const MonitoringPlan({
    required this.id,
    required this.title,
    required this.status,
    required this.items,
  });

  factory MonitoringPlan.fromJson(Map<String, dynamic> json) {
    return MonitoringPlan(
      id: json['id'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      items: (json['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(MonitoringPlanItem.fromJson)
          .toList(growable: false),
    );
  }

  final int id;
  final String title;
  final String status;
  final List<MonitoringPlanItem> items;

  /// The first ordered item that can still be performed today.
  ///
  /// Unsupported assessments are skipped only if every remaining item was
  /// already completed; they surface as "Not available yet" otherwise.
  MonitoringPlanItem? get nextAvailableItem {
    for (final MonitoringPlanItem item in items) {
      if (!item.isDoneToday) {
        return item;
      }
    }
    return null;
  }
}
