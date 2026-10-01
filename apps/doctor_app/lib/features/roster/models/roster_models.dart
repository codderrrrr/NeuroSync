/// A patient's pending link request, awaiting the doctor's decision.
class PendingRequest {
  const PendingRequest({
    required this.linkId,
    required this.patientId,
    required this.patientName,
    required this.requestedAt,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) {
    return PendingRequest(
      linkId: json['id'] as int,
      patientId: json['patient_id'] as int,
      patientName: json['patient_name'] as String,
      requestedAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int linkId;
  final int patientId;
  final String patientName;
  final DateTime requestedAt;
}

/// A patient on the doctor's active roster.
class RosterPatient {
  const RosterPatient({
    required this.patientId,
    required this.patientName,
    required this.status,
    required this.linkedAt,
  });

  factory RosterPatient.fromJson(Map<String, dynamic> json) {
    return RosterPatient(
      patientId: json['patient_id'] as int,
      patientName: json['patient_name'] as String,
      status: json['status'] as String,
      linkedAt: DateTime.parse(json['linked_at'] as String),
    );
  }

  final int patientId;
  final String patientName;
  final String status;
  final DateTime linkedAt;
}
