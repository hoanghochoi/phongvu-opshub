import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/app_storage_keys.dart';

/// Manages the app's theme mode (light/dark/system).
///
/// Persists the user's choice via [SharedPreferences].
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  static String get _storageKey => AppStorageKeys.shared(_key);

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    await AppLogger.instance.info('Theme', 'Theme mode load started');
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        _mode = ThemeMode.values.firstWhere(
          (m) => m.name == stored,
          orElse: () => ThemeMode.system,
        );
        notifyListeners();
      }
      await AppLogger.instance.info(
        'Theme',
        'Theme mode load succeeded',
        context: {'storedMode': stored, 'mode': _mode.name},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'Theme',
        'Theme mode load failed',
        error: error,
      );
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    await AppLogger.instance.info(
      'Theme',
      'Theme mode change started',
      context: {'from': _mode.name, 'to': mode.name},
    );
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
      await AppLogger.instance.info(
        'Theme',
        'Theme mode change succeeded',
        context: {'mode': mode.name},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'Theme',
        'Theme mode change failed',
        error: error,
        context: {'mode': mode.name},
      );
    }
  }

  /// Convenience toggle: light → dark → system → light
  Future<void> cycle() async {
    final next = switch (_mode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    await setMode(next);
  }
}
