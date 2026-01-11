import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ui_settings.dart';
import '../common_providers.dart';

class UiSettingsNotifier extends Notifier<UiSettings> {
  static const _keyHexDisplay = 'ui_hex_display';
  static const _keyHexSend = 'ui_hex_send';
  static const _keyShowTimestamp = 'ui_show_timestamp';
  static const _keyShowSent = 'ui_show_sent';
  static const _keyBlockIntervalMs = 'ui_block_interval_ms';
  static const _keyLineMode = 'ui_line_mode';
  static const _keyPreferredReceiveMode = 'ui_preferred_receive_mode';
  // Newline settings keys
  static const _keyAppendNewline = 'ui_append_newline';
  static const _keyNewlineMode = 'ui_newline_mode';
  static const _keyEnableAnsi = 'ui_enable_ansi';
  static const _keyLogBufferSize = 'ui_log_buffer_size';

  @override
  UiSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return UiSettings(
      hexDisplay: prefs.getBool(_keyHexDisplay) ?? false,
      hexSend: prefs.getBool(_keyHexSend) ?? false,
      showTimestamp: prefs.getBool(_keyShowTimestamp) ?? true,
      showSent: prefs.getBool(_keyShowSent) ?? true,
      blockIntervalMs: prefs.getInt(_keyBlockIntervalMs) ?? 20,
      receiveMode: (prefs.getBool(_keyLineMode) ?? false)
          ? ReceiveMode.line
          : ReceiveMode.block,
      preferredReceiveMode: (prefs.getBool(_keyPreferredReceiveMode) ?? false)
          ? ReceiveMode.line
          : ReceiveMode.block,
      appendNewline: prefs.getBool(_keyAppendNewline) ?? false,
      newlineMode: NewlineMode
          .values[prefs.getInt(_keyNewlineMode) ?? NewlineMode.lf.index],
      enableAnsi: prefs.getBool(_keyEnableAnsi) ?? false,
      logBufferSize: prefs.getInt(_keyLogBufferSize) ?? 128,
    );
  }

  void setHexDisplay(bool value) {
    final newHexDisplay = value;
    final currentReceiveMode = state.receiveMode;

    if (newHexDisplay) {
      // Switching to HEX mode: save current preference and force block mode
      state = state.copyWith(
        hexDisplay: true,
        receiveMode: ReceiveMode.block,
        preferredReceiveMode: currentReceiveMode, // Save user's preference
      );
      ref.read(sharedPreferencesProvider).setBool(_keyHexDisplay, true);
      ref.read(sharedPreferencesProvider).setBool(_keyLineMode, false);
      ref.read(sharedPreferencesProvider).setBool(
          _keyPreferredReceiveMode, currentReceiveMode == ReceiveMode.line);
    } else {
      // Switching to text mode: restore user's preference
      final preferredMode = state.preferredReceiveMode;
      state = state.copyWith(
        hexDisplay: false,
        receiveMode: preferredMode,
      );
      ref.read(sharedPreferencesProvider).setBool(_keyHexDisplay, false);
      ref
          .read(sharedPreferencesProvider)
          .setBool(_keyLineMode, preferredMode == ReceiveMode.line);
    }
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

  void setFrameIntervalMs(int value) {
    state = state.copyWith(blockIntervalMs: value);
    ref.read(sharedPreferencesProvider).setInt(_keyBlockIntervalMs, value);
  }

  void setReceiveMode(ReceiveMode mode) {
    state = state.copyWith(
      receiveMode: mode,
      preferredReceiveMode: mode,
    );
    ref
        .read(sharedPreferencesProvider)
        .setBool(_keyLineMode, mode == ReceiveMode.line);
    ref
        .read(sharedPreferencesProvider)
        .setBool(_keyPreferredReceiveMode, mode == ReceiveMode.line);
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
}

final uiSettingsProvider =
    NotifierProvider.autoDispose<UiSettingsNotifier, UiSettings>(
        UiSettingsNotifier.new);
