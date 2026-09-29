/// Static application configuration.
///
/// The API base URL is compiled in so a single build can be pointed at any
/// environment:
///
/// ```bash
/// flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://192.168.1.10:8000
/// ```
///
/// The default targets the Android emulator's alias for the host machine.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'NEUROSYNC_API_BASE_URL',
    defaultValue: 'http://192.168.3.109:8000',
  );

  static const Duration requestTimeout = Duration(seconds: 20);
}
