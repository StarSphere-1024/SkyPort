import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'common_providers.dart';

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
    return ThemeMode.system;
  }

  void toggleTheme() {
    if (state == ThemeMode.light) {
      state = ThemeMode.dark;
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
    final themeString = switch (state) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    prefs.setString(_themeKey, themeString);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeColorNotifier extends Notifier<Color> {
  static const String _themeColorKey = 'theme_color';
  static const Color defaultColor = Colors.blue;

  @override
  Color build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final colorValue = prefs.getInt(_themeColorKey);
    return colorValue == null ? defaultColor : Color(colorValue);
  }

  void setThemeColor(Color color) {
    state = color;
    ref
        .read(sharedPreferencesProvider)
        .setInt(_themeColorKey, color.toARGB32());
  }
}

final themeColorProvider = NotifierProvider<ThemeColorNotifier, Color>(
  ThemeColorNotifier.new,
);

final hasManualThemeColorProvider = Provider<bool>((ref) {
  ref.watch(themeColorProvider);
  return ref.read(sharedPreferencesProvider).getInt('theme_color') != null;
});

enum ThemeColorSource { system, manual, defaultColor }

class ThemeColorResolution {
  const ThemeColorResolution(this.seed, this.source);
  final Color seed;
  final ThemeColorSource source;
}

ThemeColorResolution resolveThemeColor({
  required bool dynamicEnabled,
  required Color? manualSeed,
  required Color? systemAccent,
  required Brightness brightness,
}) {
  if (dynamicEnabled && systemAccent != null) {
    return ThemeColorResolution(systemAccent, ThemeColorSource.system);
  }
  if (manualSeed != null) {
    return ThemeColorResolution(manualSeed, ThemeColorSource.manual);
  }
  return const ThemeColorResolution(
    ThemeColorNotifier.defaultColor,
    ThemeColorSource.defaultColor,
  );
}

class DynamicColorEnabledNotifier extends Notifier<bool> {
  static const _enabledKey = 'dynamic_color_enabled';
  static const _initializedKey = 'dynamic_color_preference_initialized';

  @override
  bool build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final initialized = prefs.getBool(_initializedKey) ?? false;
    final saved = prefs.getBool(_enabledKey);
    final hasLegacyPreferences = prefs.getKeys().any(
      (key) => key != _enabledKey && key != _initializedKey,
    );
    final enabled = initialized ? saved ?? true : !hasLegacyPreferences;
    prefs.setBool(_enabledKey, enabled);
    prefs.setBool(_initializedKey, true);
    return enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (!await prefs.setBool(_enabledKey, enabled)) {
      throw StateError('Could not save dynamic color preference');
    }
    if (!await prefs.setBool(_initializedKey, true)) {
      throw StateError('Could not save dynamic color migration state');
    }
    state = enabled;
  }
}

final dynamicColorEnabledProvider =
    NotifierProvider<DynamicColorEnabledNotifier, bool>(
      DynamicColorEnabledNotifier.new,
    );

class SystemAccentColorNotifier extends Notifier<Color?> {
  @override
  Color? build() => null;

  void setColor(Color? color) => state = color;
}

final systemAccentColorProvider =
    NotifierProvider<SystemAccentColorNotifier, Color?>(
      SystemAccentColorNotifier.new,
    );
