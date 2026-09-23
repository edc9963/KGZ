import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's light/dark/system preference locally (per device) so
/// it applies before sign-in (splash screen, login page) and offline, and
/// does not need to round-trip through the cloud-synced [AppData.settings]
/// like other account preferences do.
class ThemeModeController extends ChangeNotifier {
  ThemeModeController(this._preferences, {ThemeMode initialMode = ThemeMode.system})
    : _mode = initialMode;

  static const _prefsKey = 'theme_mode';

  final SharedPreferences _preferences;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Reads the stored preference synchronously (used at bootstrap, before
  /// the controller itself exists) so the very first frame — including the
  /// splash screen — can already render in the right brightness.
  static ThemeMode readStored(SharedPreferences preferences) {
    return _decode(preferences.getString(_prefsKey));
  }

  static ThemeMode _decode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _preferences.setString(_prefsKey, _encode(mode));
  }
}
