import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_token_store.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/check_ins/data/check_in_repository.dart';
import 'features/check_ins/state/check_in_controller.dart';
import 'features/doctor_links/data/doctor_link_repository.dart';
import 'features/doctor_links/state/doctor_link_controller.dart';
import 'features/medication/data/medication_repository.dart';
import 'features/medication/state/medication_controller.dart';
import 'features/monitoring/data/monitoring_repository.dart';
import 'features/monitoring/state/monitoring_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // One in-memory token cache shared by the API client and the auth controller,
  // so requests never wait on secure storage.
  final SessionTokenCache tokenCache = SessionTokenCache();
  final SessionTokenStore tokenStore = SecureSessionTokenStore();
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

  final DoctorLinkController doctorLinkController = DoctorLinkController(
    repository: DoctorLinkRepository(apiClient: apiClient),
  );

  final CheckInController checkInController = CheckInController(
    repository: CheckInRepository(apiClient: apiClient),
  );

  final MonitoringController monitoringController = MonitoringController(
    repository: MonitoringRepository(apiClient: apiClient),
  );

  final MedicationController medicationController = MedicationController(
    repository: MedicationRepository(apiClient: apiClient),
  );

  runApp(
    NeuroSyncApp(
      authController: authController,
      doctorLinkController: doctorLinkController,
      checkInController: checkInController,
      monitoringController: monitoringController,
      medicationController: medicationController,
    ),
  );
}
