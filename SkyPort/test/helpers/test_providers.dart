import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/services/serial_port_service.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/models/ui_settings.dart';
import 'mock_classes.dart';

/// Creates a test ProviderContainer with common overrides
///
/// This helper creates a ProviderContainer for testing with:
/// - Mocked SerialPortServiceInterface
/// - Fake SharedPreferences
/// - Optional additional overrides
///
/// Example:
/// ```dart
/// late ProviderContainer container;
/// setUp(() {
///   final mockService = MockSerialPortService();
///   final mockPrefs = FakeSharedPreferences();
///   container = createTestContainer(
///     serialPortService: mockService,
///     sharedPreferences: mockPrefs,
///   );
/// });
/// tearDown(() {
///   container.dispose();
/// });
/// ```
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

/// Creates a ProviderContainer with fake SharedPreferences and default settings
///
/// This is a convenience function for tests that need a basic container
/// with working SharedPreferences but don't need custom SerialPortService.
ProviderContainer createContainerWithFakePrefs() {
  final prefs = FakeSharedPreferences();
  return createTestContainer(
    sharedPreferences: prefs,
  );
}

/// Mock UiSettingsNotifier for testing
///
/// This allows tests to control the UI settings state directly
/// without going through the normal provider logic.
class TestUiSettingsNotifier extends UiSettingsNotifier {
  final UiSettings _settings;

  TestUiSettingsNotifier(this._settings);

  @override
  UiSettings build() => _settings;
}

/// Mock SerialConfigNotifier for testing
///
/// This allows tests to control the serial config state directly
/// without going through the normal provider logic.
class TestSerialConfigNotifier extends SerialConfigNotifier {
  final SerialConfig? _config;

  TestSerialConfigNotifier(this._config);

  @override
  SerialConfig? build() => _config;
}

/// Creates a test container with overridden UI settings
///
/// Example:
/// ```dart
/// final container = createTestContainerWithUiSettings(
///   const UiSettings(hexDisplay: true, showTimestamp: false),
/// );
/// ```
ProviderContainer createTestContainerWithUiSettings(UiSettings settings) {
  return ProviderContainer(
    overrides: [
      uiSettingsProvider.overrideWith(() => TestUiSettingsNotifier(settings)),
    ],
  );
}

/// Creates a test container with overridden serial config
///
/// Example:
/// ```dart
/// final container = createTestContainerWithSerialConfig(
///   SerialConfig(portName: 'COM1', baudRate: 115200),
/// );
/// ```
ProviderContainer createTestContainerWithSerialConfig(SerialConfig? config) {
  return ProviderContainer(
    overrides: [
      serialConfigProvider.overrideWith(() => TestSerialConfigNotifier(config)),
    ],
  );
}

/// Setup function for all tests
///
/// Call this in setUpAll() to register fallback values for mocktail.
/// This should be called once at the beginning of a test file.
///
/// Example:
/// ```dart
/// void main() {
///   setUpAll(() {
///     setupTestDefaults();
///   });
///
///   group('MyTests', () {
///     // tests here
///   });
/// }
/// ```
void setupTestDefaults() {
  registerFallbackValues();
}

/// Extension to add pump() method to ProviderContainer
///
/// This allows waiting for async operations in providers.
extension ProviderContainerPump on ProviderContainer {
  /// Pump the provider container to process async updates
  Future<void> pump() async {
    await Future.microtask(() {});
  }
}
