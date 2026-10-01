import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/session_token_store.dart';
import '../data/auth_repository.dart';
import '../models/auth_result.dart';
import '../models/doctor.dart';

/// Where the application is in the sign-in lifecycle.
enum AuthStatus {
  /// A stored session is still being checked.
  checking,

  /// Nobody is signed in.
  signedOut,

  /// A doctor is signed in.
  signedIn,
}

/// Owns authentication state and the persisted session token.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required SessionTokenStore tokenStore,
    required SessionTokenCache tokenCache,
  })  : _repository = repository,
        _tokenStore = tokenStore,
        _tokenCache = tokenCache;

  final AuthRepository _repository;
  final SessionTokenStore _tokenStore;
  final SessionTokenCache _tokenCache;

  AuthStatus _status = AuthStatus.checking;
  Doctor? _doctor;
  String? _errorMessage;
  bool _isSubmitting = false;

  AuthStatus get status => _status;
  Doctor? get doctor => _doctor;
  String? get errorMessage => _errorMessage;
  bool get isSubmitting => _isSubmitting;

  /// Restores a persisted session on launch by asking the API who we are.
  ///
  /// The stored token is verified against `GET /doctor/auth/me` rather than
  /// trusted, so a revoked or expired session lands on the login screen.
  Future<void> restoreSession() async {
    final String? token = await _tokenStore.read();
    if (token == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _tokenCache.value = token;
    try {
      _doctor = await _repository.currentDoctor();
      _status = AuthStatus.signedIn;
    } on ApiException {
      _tokenCache.value = null;
      await _tokenStore.clear();
      _doctor = null;
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _submit(
        () => _repository.signUp(name: name, email: email, password: password));
  }

  Future<bool> signIn({required String email, required String password}) {
    return _submit(() => _repository.logIn(email: email, password: password));
  }

  Future<void> signOut() async {
    try {
      await _repository.logOut();
    } on ApiException {
      // Signing out locally must succeed even if the server call fails.
    }
    _tokenCache.value = null;
    await _tokenStore.clear();
    _doctor = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _submit(Future<AuthResult> Function() action) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final AuthResult result = await action();
      _tokenCache.value = result.accessToken;
      await _tokenStore.write(result.accessToken);
      _doctor = result.doctor;
      _status = AuthStatus.signedIn;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
