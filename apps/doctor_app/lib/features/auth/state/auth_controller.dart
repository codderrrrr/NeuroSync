import 'package:neurosync_core/auth/auth_controller.dart' as core;

export 'package:neurosync_core/auth/auth_controller.dart' show AuthStatus;

import '../models/doctor.dart';

/// The doctor portal sign-in state.
///
/// The lifecycle is the shared one; this says which user it signs in as.
class AuthController extends core.AuthController<Doctor> {
  AuthController({
    required super.repository,
    required super.tokenStore,
    required super.tokenCache,
  });

  /// The signed-in doctor, or null when nobody is signed in.
  Doctor? get doctor => user;
}
