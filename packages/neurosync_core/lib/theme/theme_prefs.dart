import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Which mood the application is in.
///
/// The patient decides. Some use the app in the evening and in bed, where a
/// bright page is uncomfortable; some use it in daylight, where a dark one is.
class ThemePrefs {
  const ThemePrefs._();

  static const String _key = 'neurosync.theme_mode';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// The stored choice, or null when the patient has not made one.
  ///
  /// A failure to read is not a failure: the app falls back to following the
  /// system, which is a reasonable answer until the patient says otherwise.
  static Future<ThemeMode?> read() async {
    try {
      final String? value = await _storage.read(key: _key);
      return _parse(value);
    } catch (_) {
      return null;
    }
  }

  /// Remembers the choice.
  static Future<void> write(ThemeMode mode) async {
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {
      // A preference that will not save is a preference the patient has to
      // set again, not a reason to fail the change they just made.
    }
  }

  /// Forgets the choice, so the app follows the system again.
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing to do: the stored value stays, and the app carries on.
    }
  }

  static ThemeMode? _parse(String? value) {
    for (final ThemeMode mode in ThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return null;
  }
}
