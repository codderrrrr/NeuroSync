import 'package:neurosync_core/neurosync_core.dart';

/// The signed-in doctor, including the personal link code patients type.
class Doctor extends AuthUser {
  const Doctor({
    required super.id,
    required super.email,
    required super.name,
    required super.createdAt,
    this.code,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      code: json['code'] as String?,
    );
  }

  /// The doctor's shareable link code, or null when the account predates
  /// codes and one has not been issued yet.
  final String? code;
}
