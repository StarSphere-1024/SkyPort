import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import 'common_providers.dart';

class UiSettingsNotifier extends Notifier<UiSettings> {
  static const _keyHexDisplay = 'ui_hex_display';
  static const _keyShowTimestamp = 'ui_show_timestamp';
  static const _keyShowSent = 'ui_show_sent';
  static const _keyEnableAnsi = 'ui_enable_ansi';
  static const _keyLogExportPath = 'ui_log_export_path';
  static const _keyAutoCheckUpdates = 'ui_auto_check_updates';

  @override
  UiSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return UiSettings(
      hexDisplay: prefs.getBool(_keyHexDisplay) ?? false,
      showTimestamp: prefs.getBool(_keyShowTimestamp) ?? true,
      showSent: prefs.getBool(_keyShowSent) ?? true,
      enableAnsi: prefs.getBool(_keyEnableAnsi) ?? false,
      logExportPath: prefs.getString(_keyLogExportPath) ?? '',
      autoCheckUpdates: prefs.getBool(_keyAutoCheckUpdates) ?? true,
    );
  }

  void setHexDisplay(bool value) =>
      _set(_keyHexDisplay, state.copyWith(hexDisplay: value), value);
  void setShowTimestamp(bool value) =>
      _set(_keyShowTimestamp, state.copyWith(showTimestamp: value), value);
  void setShowSent(bool value) =>
      _set(_keyShowSent, state.copyWith(showSent: value), value);
  void setEnableAnsi(bool value) =>
      _set(_keyEnableAnsi, state.copyWith(enableAnsi: value), value);
  void setLogExportPath(String value) =>
      _set(_keyLogExportPath, state.copyWith(logExportPath: value), value);

  Future<void> setAutoCheckUpdates(bool value) async {
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(_keyAutoCheckUpdates, value);
    if (!saved) throw StateError('Could not save automatic update preference');
    state = state.copyWith(autoCheckUpdates: value);
  }

  void _set(String key, UiSettings updated, Object value) {
    state = updated;
    final prefs = ref.read(sharedPreferencesProvider);
    switch (value) {
      case bool boolValue:
        prefs.setBool(key, boolValue);
      case String stringValue:
        prefs.setString(key, stringValue);
    }
  }
}

final uiSettingsProvider = NotifierProvider<UiSettingsNotifier, UiSettings>(
  UiSettingsNotifier.new,
);
