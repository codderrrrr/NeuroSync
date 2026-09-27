import 'patient.dart';

/// An authenticated session returned by signup and login.
class AuthResult {
  const AuthResult({
    required this.patient,
    required this.accessToken,
    required this.expiresAt,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      patient: Patient.fromJson(json['patient'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final Patient patient;
  final String accessToken;
  final DateTime expiresAt;
}
