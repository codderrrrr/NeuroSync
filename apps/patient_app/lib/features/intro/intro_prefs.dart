import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One-time onboarding flag, stored with the platform secure store so no
/// additional dependency is introduced.
class IntroPrefs {
  const IntroPrefs._();

  static const String _seenKey = 'neurosync.onboarding_seen';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> hasSeenOnboarding() async {
    final String? value = await _storage.read(key: _seenKey);
    return value == '1';
  }

  static Future<void> markSeenOnboarding() =>
      _storage.write(key: _seenKey, value: '1');
}
