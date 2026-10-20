import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/exceptions/data/exception_repository.dart';
import 'features/exceptions/state/exception_controller.dart';
import 'features/patients/data/assignment_repository.dart';
import 'features/patients/state/assignment_controller.dart';
import 'features/roster/data/roster_repository.dart';
import 'features/roster/state/roster_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // One in-memory token cache shared by the API client and the auth controller,
  // so requests never wait on secure storage.
  final SessionTokenCache tokenCache = SessionTokenCache();
  final SessionTokenStore tokenStore =
      SecureSessionTokenStore(storageKey: 'neurosync_doctor.session_token');
  final http.Client httpClient = http.Client();

  final ApiClient apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    httpClient: httpClient,
    sessionToken: tokenCache,
    timeout: AppConfig.requestTimeout,
  );

  final AuthController authController = AuthController(
    repository: AuthRepository(apiClient: apiClient),
    tokenStore: tokenStore,
    tokenCache: tokenCache,
  );

  final RosterController rosterController = RosterController(
    repository: RosterRepository(apiClient: apiClient),
  );

  final AssignmentController assignmentController = AssignmentController(
    repository: AssignmentRepository(apiClient: apiClient),
  );

  final ExceptionController exceptionController = ExceptionController(
    repository: ExceptionRepository(apiClient: apiClient),
  );

  authController.restoreSession();

  runApp(
    NeuroSyncDoctorApp(
      authController: authController,
      rosterController: rosterController,
      assignmentController: assignmentController,
      exceptionController: exceptionController,
    ),
  );
}
