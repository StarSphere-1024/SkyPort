import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'serial_provider.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _themeKey = 'theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return _loadThemeMode(prefs);
  }

  ThemeMode _loadThemeMode(SharedPreferences prefs) {
    final themeString = prefs.getString(_themeKey);
    if (themeString == 'light') return ThemeMode.light;
    if (themeString == 'dark') return ThemeMode.dark;
    return ThemeMode.system; // Default to follow system
  }

  void toggleTheme() {
    if (state == ThemeMode.light) {
      state = ThemeMode.dark;
    } else if (state == ThemeMode.dark) {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.light;
    }
    _saveThemeMode();
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _saveThemeMode();
  }

  void _saveThemeMode() {
    final prefs = ref.read(sharedPreferencesProvider);
    String themeString;
    if (state == ThemeMode.light) {
      themeString = 'light';
    } else if (state == ThemeMode.dark) {
      themeString = 'dark';
    } else {
      themeString = 'system';
    }
    prefs.setString(_themeKey, themeString);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
