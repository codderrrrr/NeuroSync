/// Static application configuration.
///
/// The API base URL is compiled in so a single build can be pointed at any
/// environment:
///
/// ```bash
/// flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://192.168.1.10:8000
/// ```
///
/// The default is the development machine's LAN address, so a physical device
/// on the same network can reach the backend. Override it per run; Android
/// emulators can use `http://10.0.2.2:8000` to reach the host instead.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'NEUROSYNC_API_BASE_URL',
    defaultValue: 'http://192.168.80.90:8000',
  );

  static const Duration requestTimeout = Duration(seconds: 20);
}
