/// Static application configuration.
///
/// The API base URL is compiled in so a single build can be pointed at any
/// environment:
///
/// ```bash
/// flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://192.168.3.111:8000
/// ```
///
/// The default is the development machine's LAN address, so a physical device
/// on the same network can reach the backend. Override it per run; Android
/// emulators can use `http://10.0.2.2:8000` to reach the host instead.
///
/// **This address changes.** A laptop on DHCP is given a new one whenever it
/// rejoins a network, and the address baked in here will be stale the next
/// time that happens - the app will hang until it times out, because the
/// request is going somewhere that does not answer. Run
/// `uv run python scripts/dev_api_address.py` for the current one, and pass
/// it in with `--dart-define` rather than relying on the default.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'NEUROSYNC_API_BASE_URL',
    defaultValue: 'http://192.168.3.111:8000',
  );

  static const Duration requestTimeout = Duration(seconds: 20);
}
