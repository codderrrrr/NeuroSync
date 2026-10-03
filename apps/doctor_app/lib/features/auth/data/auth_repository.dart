import '../../../core/network/api_client.dart';
import '../models/auth_result.dart';
import '../models/doctor.dart';

/// Doctor authentication endpoints (`/doctor/auth/*`).
class AuthRepository {
  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('/doctor/auth/signup', <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(body);
  }

  Future<AuthResult> logIn(
      {required String email, required String password}) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('/doctor/auth/login', <String, dynamic>{
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(body);
  }

  Future<Doctor> currentDoctor() async {
    final Map<String, dynamic> body =
        await _apiClient.getObject('/doctor/auth/me');
    return Doctor.fromJson(body);
  }

  Future<void> logOut() => _apiClient.postEmpty('/doctor/auth/logout');
}
