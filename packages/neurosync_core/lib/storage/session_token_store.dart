import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token so sign-in survives application restarts.
abstract class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

/// Stores the session token in the platform secure storage
/// (iOS Keychain / Android Keystore).
///
/// The storage key is the caller's, so the two applications keep their tokens
/// apart: a doctor signing in on a shared device must not find a patient's
/// session already there.
class SecureSessionTokenStore implements SessionTokenStore {
  SecureSessionTokenStore(
      {required this.storageKey, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// The key the token is stored under.
  final String storageKey;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: storageKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: storageKey, value: token);

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
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
