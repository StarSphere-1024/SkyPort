import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ui_settings.dart';
import '../common_providers.dart';

class UiSettingsNotifier extends Notifier<UiSettings> {
  static const _keyHexDisplay = 'ui_hex_display';
  static const _keyHexSend = 'ui_hex_send';
  static const _keyShowTimestamp = 'ui_show_timestamp';
  static const _keyShowSent = 'ui_show_sent';
  // Newline settings keys
  static const _keyAppendNewline = 'ui_append_newline';
  static const _keyNewlineMode = 'ui_newline_mode';
  static const _keyEnableAnsi = 'ui_enable_ansi';
  static const _keyLogBufferSize = 'ui_log_buffer_size';
  // Auto-send settings keys
  static const _keyAutoSendEnabled = 'ui_auto_send_enabled';
  static const _keyAutoSendIntervalMs = 'ui_auto_send_interval_ms';

  @override
  UiSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return UiSettings(
      hexDisplay: prefs.getBool(_keyHexDisplay) ?? false,
      hexSend: prefs.getBool(_keyHexSend) ?? false,
      showTimestamp: prefs.getBool(_keyShowTimestamp) ?? true,
      showSent: prefs.getBool(_keyShowSent) ?? true,
      appendNewline: prefs.getBool(_keyAppendNewline) ?? false,
      newlineMode: NewlineMode
          .values[prefs.getInt(_keyNewlineMode) ?? NewlineMode.lf.index],
      enableAnsi: prefs.getBool(_keyEnableAnsi) ?? false,
      logBufferSize: prefs.getInt(_keyLogBufferSize) ?? 128,
      autoSendEnabled: prefs.getBool(_keyAutoSendEnabled) ?? false,
      autoSendIntervalMs: prefs.getInt(_keyAutoSendIntervalMs) ?? 1000,
    );
  }

  void setHexDisplay(bool value) {
    // Simplified: no longer need to switch receive modes
    // Stream buffering architecture handles both hex and text uniformly
    state = state.copyWith(hexDisplay: value);
    ref.read(sharedPreferencesProvider).setBool(_keyHexDisplay, value);
  }

  void setHexSend(bool value) {
    state = state.copyWith(hexSend: value);
    ref.read(sharedPreferencesProvider).setBool(_keyHexSend, value);
  }

  void setShowTimestamp(bool value) {
    state = state.copyWith(showTimestamp: value);
    ref.read(sharedPreferencesProvider).setBool(_keyShowTimestamp, value);
  }

  void setShowSent(bool value) {
    state = state.copyWith(showSent: value);
    ref.read(sharedPreferencesProvider).setBool(_keyShowSent, value);
  }

  void setAppendNewline(bool value) {
    state = state.copyWith(appendNewline: value);
    ref.read(sharedPreferencesProvider).setBool(_keyAppendNewline, value);
  }

  void setNewlineMode(NewlineMode mode) {
    state = state.copyWith(newlineMode: mode);
    ref.read(sharedPreferencesProvider).setInt(_keyNewlineMode, mode.index);
  }

  void setEnableAnsi(bool value) {
    state = state.copyWith(enableAnsi: value);
    ref.read(sharedPreferencesProvider).setBool(_keyEnableAnsi, value);
  }

  void setLogBufferSize(int size) {
    state = state.copyWith(logBufferSize: size);
    ref.read(sharedPreferencesProvider).setInt(_keyLogBufferSize, size);
  }

  void setAutoSendEnabled(bool value) {
    state = state.copyWith(autoSendEnabled: value);
    ref.read(sharedPreferencesProvider).setBool(_keyAutoSendEnabled, value);
  }

  void setAutoSendIntervalMs(int value) {
    state = state.copyWith(autoSendIntervalMs: value);
    ref.read(sharedPreferencesProvider).setInt(_keyAutoSendIntervalMs, value);
  }
}

final uiSettingsProvider =
    NotifierProvider.autoDispose<UiSettingsNotifier, UiSettings>(
        UiSettingsNotifier.new);
