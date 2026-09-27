import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token so sign-in survives application restarts.
abstract class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

/// Stores the session token in the platform secure storage
/// (iOS Keychain / Android Keystore).
class SecureSessionTokenStore implements SessionTokenStore {
  SecureSessionTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'neurosync.session_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _tokenKey);
}

/// In-memory store used by tests and local previews.
class InMemorySessionTokenStore implements SessionTokenStore {
  InMemorySessionTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// Keeps the session token in memory for the current run.
///
/// Reading secure storage on every request would add platform-channel latency
/// to each call, so the token is cached once and shared with the API client.
class SessionTokenCache {
  String? value;
}
