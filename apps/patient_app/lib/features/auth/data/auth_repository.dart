import '../../../core/network/api_client.dart';
import '../models/auth_result.dart';
import '../models/patient.dart';

/// Patient authentication endpoints.
class AuthRepository {
  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('/auth/signup', <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(body);
  }

  Future<AuthResult> logIn(
      {required String email, required String password}) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('/auth/login', <String, dynamic>{
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(body);
  }

  Future<Patient> currentPatient() async {
    final Map<String, dynamic> body = await _apiClient.getObject('/auth/me');
    return Patient.fromJson(body);
  }

  Future<void> logOut() => _apiClient.postEmpty('/auth/logout');
}
