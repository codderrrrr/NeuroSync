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
    required this.parameters,
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
      parameters: <String, Object>{
        ...(json['parameters'] as Map<String, dynamic>? ??
            const <String, dynamic>{}),
      },
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

  /// What the doctor set for this item beyond the recording length: which hand,
  /// how fast, how many turns, the phrase to write. The server resolves these
  /// against the catalog, so they are always a complete set.
  final Map<String, Object> parameters;

  /// The duration a runner should use for this item.
  int get effectiveDurationSeconds =>
      durationSeconds ?? assessment.defaultDurationSeconds;

  /// One setting's value, falling back to the catalog default.
  Object parameterValue(String key, Object fallback) =>
      parameters[key] ?? fallback;

  int get turns => (parameterValue('turns', 2) as num).toInt();

  int get spiralSizePercent =>
      (parameterValue('size_percent', 70) as num).toInt();

  int get lineLengthPercent =>
      (parameterValue('line_length_percent', 70) as num).toInt();

  int get repetitions => (parameterValue('repetitions', 1) as num).toInt();

  String get phrase => parameterValue('phrase', 'NeuroSync') as String;

  /// How the patient is asked to move, as one of the declared speeds.
  String get pacing => parameterValue('pacing', 'comfortable') as String;

  /// "Your test is set up as" lines, in the order the catalog declares them.
  ///
  /// Only declared settings with a value the item carries are listed, so the
  /// app never shows a raw setting name it does not understand.
  List<({String label, String value})> get settings {
    final List<({String label, String value})> described =
        <({String label, String value})>[];
    for (final AssessmentSetting setting in assessment.parameters) {
      if (!parameters.containsKey(setting.key)) {
        continue;
      }
      described.add((
        label: setting.label,
        value: setting.describe(parameters[setting.key]!),
      ));
    }
    return described;
  }

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
