import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/services/serial_port_service.dart';

import 'mock_classes.dart';

ProviderContainer createTestContainer({
  SerialPortServiceInterface? serialPortService,
  SharedPreferences? sharedPreferences,
  List overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      if (serialPortService != null)
        serialPortServiceProvider.overrideWithValue(serialPortService),
      if (sharedPreferences != null)
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ...overrides,
    ],
  );
}

ProviderContainer createContainerWithFakePrefs() {
  final prefs = FakeSharedPreferences();
  return createTestContainer(sharedPreferences: prefs);
}

class TestUiSettingsNotifier extends UiSettingsNotifier {
  TestUiSettingsNotifier(this._settings);

  final UiSettings _settings;

  @override
  UiSettings build() => _settings;
}

ProviderContainer createTestContainerWithUiSettings(UiSettings settings) {
  return ProviderContainer(
    overrides: [
      uiSettingsProvider.overrideWith(() => TestUiSettingsNotifier(settings)),
    ],
  );
}

void setupTestDefaults() {
  registerFallbackValues();
}

extension ProviderContainerPump on ProviderContainer {
  Future<void> pump() async {
    await Future.microtask(() {});
  }
}
