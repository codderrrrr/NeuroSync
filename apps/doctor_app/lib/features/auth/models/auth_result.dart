import 'doctor.dart';

/// An authenticated session returned by signup and login.
class AuthResult {
  const AuthResult({
    required this.doctor,
    required this.accessToken,
    required this.expiresAt,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      doctor: Doctor.fromJson(json['doctor'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final Doctor doctor;
  final String accessToken;
  final DateTime expiresAt;
}
