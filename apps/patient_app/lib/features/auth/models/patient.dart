import 'package:neurosync_core/neurosync_core.dart';

/// Basic patient profile returned by the API.
class Patient extends AuthUser {
  const Patient({
    required super.id,
    required super.email,
    required super.name,
    required super.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
