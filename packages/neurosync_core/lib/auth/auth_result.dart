/// An authenticated session: who signed in, and the token that says so.
class AuthResult<TUser> {
  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.expiresAt,
  });

  /// Reads the result of a sign-in, taking the user out of [userField].
  ///
  /// The two roles return their user under a different key, so the key is
  /// the caller's to name.
  factory AuthResult.fromJson(
    Map<String, dynamic> json, {
    required String userField,
    required TUser Function(Map<String, dynamic> json) parseUser,
  }) {
    return AuthResult(
      user: parseUser(json[userField] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final TUser user;
  final String accessToken;
  final DateTime expiresAt;
}
