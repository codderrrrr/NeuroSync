/// Lifecycle of a patient's link to a doctor, as reported by the API.
enum DoctorLinkStatus {
  pending,
  active;

  static DoctorLinkStatus fromApi(String value) {
    switch (value) {
      case 'pending':
        return DoctorLinkStatus.pending;
      case 'active':
        return DoctorLinkStatus.active;
      default:
        throw FormatException('Unknown doctor link status: $value');
    }
  }

  /// Display label used in the UI.
  String get label => this == DoctorLinkStatus.active ? 'ACTIVE' : 'PENDING';
}

/// A patient's link to a doctor.
///
/// The API only exposes the doctor identifier and the link state, so no doctor
/// detail (name, contact information) is modelled here.
class DoctorLink {
  const DoctorLink({
    required this.doctorId,
    required this.status,
    required this.createdAt,
  });

  factory DoctorLink.fromJson(Map<String, dynamic> json) {
    return DoctorLink(
      doctorId: json['doctor_id'] as int,
      status: DoctorLinkStatus.fromApi(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int doctorId;
  final DoctorLinkStatus status;
  final DateTime createdAt;

  bool get isPending => status == DoctorLinkStatus.pending;
}
