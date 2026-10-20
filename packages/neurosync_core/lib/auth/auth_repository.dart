import '../network/api_client.dart';
import 'auth_result.dart';
import 'auth_user.dart';

/// Authentication endpoints, for whichever role is signing in.
///
/// The two roles differ only in where their endpoints live and what their
/// user is called, so both are the caller's to name.
class AuthRepository<TUser extends AuthUser> {
  AuthRepository({
    required ApiClient apiClient,
    required this.basePath,
    required this.userField,
    required this.parseUser,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Where this role's authentication endpoints live, e.g. `/auth`.
  final String basePath;

  /// The key the signed-in user is returned under, e.g. `patient`.
  final String userField;

  /// How to read the signed-in user out of the response.
  final TUser Function(Map<String, dynamic> json) parseUser;

  Future<AuthResult<TUser>> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('$basePath/signup', <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(
      body,
      userField: userField,
      parseUser: parseUser,
    );
  }

  Future<AuthResult<TUser>> logIn(
      {required String email, required String password}) async {
    final Map<String, dynamic> body =
        await _apiClient.postObject('$basePath/login', <String, dynamic>{
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(
      body,
      userField: userField,
      parseUser: parseUser,
    );
  }

  /// Asks the server who we are, to check a stored token is still good.
  Future<TUser> currentUser() async {
    final Map<String, dynamic> body = await _apiClient.getObject('$basePath/me');
    return parseUser(body);
  }

  Future<void> logOut() => _apiClient.postEmpty('$basePath/logout');
}
