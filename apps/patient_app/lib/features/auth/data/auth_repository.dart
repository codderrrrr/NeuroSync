import 'package:neurosync_core/auth/auth_repository.dart' as core;

import '../models/patient.dart';

/// Patient authentication endpoints.
class AuthRepository extends core.AuthRepository<Patient> {
  AuthRepository({required super.apiClient})
      : super(
          basePath: '/auth',
          userField: 'patient',
          parseUser: Patient.fromJson,
        );
}
