import 'package:neurosync_core/auth/auth_controller.dart' as core;

export 'package:neurosync_core/auth/auth_controller.dart' show AuthStatus;

import '../models/patient.dart';

/// The patient application sign-in state.
///
/// The lifecycle is the shared one; this says which user it signs in as.
class AuthController extends core.AuthController<Patient> {
  AuthController({
    required super.repository,
    required super.tokenStore,
    required super.tokenCache,
  });

  /// The signed-in patient, or null when nobody is signed in.
  Patient? get patient => user;
}
