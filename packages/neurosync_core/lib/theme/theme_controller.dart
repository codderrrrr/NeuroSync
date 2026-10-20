import 'package:flutter/material.dart';

import '../theme/theme_prefs.dart';

/// Holds which mood the application is in, and remembers the choice.
///
/// The mood is the patient's to choose, so this is a controller they can
/// reach: one that follows the system until they say otherwise.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  /// Reads the stored choice.
  ///
  /// Called once, before the first frame, so the app opens in the mood the
  /// patient last chose rather than flashing the wrong one.
  Future<void> load() async {
    final ThemeMode? stored = await ThemePrefs.read();
    if (stored != null) {
      value = stored;
    }
  }

  /// Sets the mood and remembers it.
  Future<void> set(ThemeMode mode) async {
    value = mode;
    await ThemePrefs.write(mode);
  }

  /// Hands the choice back to the system.
  Future<void> followSystem() async {
    value = ThemeMode.system;
    await ThemePrefs.clear();
  }
}
