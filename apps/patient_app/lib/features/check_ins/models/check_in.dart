/// A single patient-reported symptom check-in, exactly as it was reported.
///
/// Nothing in here is scored or interpreted; the values are the patient's own
/// observations of tremor, stiffness, slowness and balance on a 0-4 scale.
class CheckIn {
  const CheckIn({
    required this.id,
    required this.recordedAt,
    required this.tremor,
    required this.stiffness,
    required this.slowness,
    required this.balance,
    required this.note,
    required this.createdAt,
  });

  final int id;

  /// When the symptoms were felt (server time, timezone included).
  final DateTime recordedAt;

  /// Severity ratings from 0 (not present) to 4 (severe), as reported.
  final int tremor;
  final int stiffness;
  final int slowness;
  final int balance;

  /// Optional free-text note, or null when the patient added none.
  final String? note;

  final DateTime createdAt;

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      id: json['id'] as int,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      tremor: json['tremor'] as int,
      stiffness: json['stiffness'] as int,
      slowness: json['slowness'] as int,
      balance: json['balance'] as int,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
