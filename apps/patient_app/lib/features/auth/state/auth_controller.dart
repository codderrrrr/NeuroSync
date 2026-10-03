import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/session_token_store.dart';
import '../data/auth_repository.dart';
import '../models/auth_result.dart';
import '../models/patient.dart';

/// Where the application is in the sign-in lifecycle.
enum AuthStatus {
  /// A stored session is still being checked.
  checking,

  /// Nobody is signed in.
  signedOut,

  /// A patient is signed in.
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
  Patient? _patient;
  String? _errorMessage;
  bool _isSubmitting = false;

  AuthStatus get status => _status;
  Patient? get patient => _patient;
  String? get errorMessage => _errorMessage;
  bool get isSubmitting => _isSubmitting;

  /// Restores a persisted session on launch by asking the API who we are.
  ///
  /// The stored token is verified against `GET /auth/me` rather than trusted,
  /// so a revoked or expired session lands on the login screen.
  Future<void> restoreSession() async {
    try {
      final String? token = await _tokenStore.read();
      if (token == null) {
        _signedOut();
        return;
      }

      _tokenCache.value = token;
      _patient = await _repository.currentPatient();
      _status = AuthStatus.signedIn;
    } catch (_) {
      // Anything can fail here -- a revoked session, an unreachable server, a
      // keystore that will not open, or a response the model cannot parse.
      // None of those may leave the status at `checking`, because the root
      // view renders `checking` as a splash screen with no way out.
      _tokenCache.value = null;
      await _discardStoredToken();
      _signedOut();
      return;
    }
    notifyListeners();
  }

  /// Clears the persisted session, ignoring a failure to do so.
  Future<void> _discardStoredToken() async {
    try {
      await _tokenStore.clear();
    } catch (_) {
      // The in-memory session is gone either way; a keystore that cannot be
      // cleared must not strand the patient on the splash screen.
    }
  }

  void _signedOut() {
    _patient = null;
    _status = AuthStatus.signedOut;
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
    } catch (_) {
      // Signing out locally must succeed even if the server call fails.
    }
    _tokenCache.value = null;
    await _discardStoredToken();
    _signedOut();
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
      _patient = result.patient;
      _status = AuthStatus.signedIn;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      // A rejected credential is never a session worth checking; without this
      // the status could stay `checking` and swap the form for the splash.
      _status = AuthStatus.signedOut;
      return false;
    } catch (_) {
      // An unexpected failure (secure storage, response parsing) must never
      // leave the patient on a silent form; describe it like any other error.
      _errorMessage = 'Something went wrong. Please try again.';
      _status = AuthStatus.signedOut;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
