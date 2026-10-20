import 'package:neurosync_core/auth/auth_repository.dart' as core;

import '../models/doctor.dart';

/// Doctor authentication endpoints.
class AuthRepository extends core.AuthRepository<Doctor> {
  AuthRepository({required super.apiClient})
      : super(
          basePath: '/doctor/auth',
          userField: 'doctor',
          parseUser: Doctor.fromJson,
        );
}
