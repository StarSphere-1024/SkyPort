import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import '../../../helpers/test_providers.dart';
import '../../../helpers/mock_classes.dart';

void main() {
  group('UiSettingsNotifier', () {
    late ProviderContainer container;
    late FakeSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = FakeSharedPreferences();
      container = createTestContainer(sharedPreferences: mockPrefs);
    });

    tearDown(() {
      container.dispose();
    });

    group('Default Values', () {
      test('loads default hexDisplay as false', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.hexDisplay, false);
      });

      test('loads default hexSend as false', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.hexSend, false);
      });

      test('loads default showTimestamp as true', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.showTimestamp, true);
      });

      test('loads default showSent as true', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.showSent, true);
      });

      test('loads default blockIntervalMs as 20', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.blockIntervalMs, 20);
      });

      test('loads default receiveMode as block', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.receiveMode, ReceiveMode.block);
      });

      test('loads default preferredReceiveMode as line', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.preferredReceiveMode, ReceiveMode.line);
      });

      test('loads default appendNewline as false', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.appendNewline, false);
      });

      test('loads default newlineMode as lf', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.newlineMode, NewlineMode.lf);
      });

      test('loads default enableAnsi as false', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.enableAnsi, false);
      });

      test('loads default logBufferSize as 128', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.logBufferSize, 128);
      });

      test('loads default autoSendEnabled as false', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.autoSendEnabled, false);
      });

      test('loads default autoSendIntervalMs as 1000', () {
        final settings = container.read(uiSettingsProvider);
        expect(settings.autoSendIntervalMs, 1000);
      });
    });

    group('Boolean Settings Updates', () {
      test('setHexDisplay updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setHexDisplay(true);

        final settings = container.read(uiSettingsProvider);
        expect(settings.hexDisplay, true);
        expect(mockPrefs.getBool('ui_hex_display'), true);
      });

      test('setHexSend updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setHexSend(true);

        final settings = container.read(uiSettingsProvider);
        expect(settings.hexSend, true);
        expect(mockPrefs.getBool('ui_hex_send'), true);
      });

      test('setShowTimestamp updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setShowTimestamp(false);

        final settings = container.read(uiSettingsProvider);
        expect(settings.showTimestamp, false);
        expect(mockPrefs.getBool('ui_show_timestamp'), false);
      });

      test('setShowSent updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setShowSent(false);

        final settings = container.read(uiSettingsProvider);
        expect(settings.showSent, false);
        expect(mockPrefs.getBool('ui_show_sent'), false);
      });

      test('setAppendNewline updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setAppendNewline(true);

        final settings = container.read(uiSettingsProvider);
        expect(settings.appendNewline, true);
        expect(mockPrefs.getBool('ui_append_newline'), true);
      });

      test('setEnableAnsi updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setEnableAnsi(true);

        final settings = container.read(uiSettingsProvider);
        expect(settings.enableAnsi, true);
        expect(mockPrefs.getBool('ui_enable_ansi'), true);
      });

      test('setAutoSendEnabled updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setAutoSendEnabled(true);

        final settings = container.read(uiSettingsProvider);
        expect(settings.autoSendEnabled, true);
        expect(mockPrefs.getBool('ui_auto_send_enabled'), true);
      });
    });

    group('Integer Settings Updates', () {
      test('setLogBufferSize updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setLogBufferSize(256);

        final settings = container.read(uiSettingsProvider);
        expect(settings.logBufferSize, 256);
        expect(mockPrefs.getInt('ui_log_buffer_size'), 256);
      });

      test('setAutoSendIntervalMs updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setAutoSendIntervalMs(500);

        final settings = container.read(uiSettingsProvider);
        expect(settings.autoSendIntervalMs, 500);
        expect(mockPrefs.getInt('ui_auto_send_interval_ms'), 500);
      });
    });

    group('Enum Settings Updates', () {
      test('setNewlineMode updates state and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setNewlineMode(NewlineMode.crlf);

        final settings = container.read(uiSettingsProvider);
        expect(settings.newlineMode, NewlineMode.crlf);
        expect(mockPrefs.getInt('ui_newline_mode'), NewlineMode.crlf.index);
      });

      test('setNewlineMode to cr updates and persists', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        notifier.setNewlineMode(NewlineMode.cr);

        final settings = container.read(uiSettingsProvider);
        expect(settings.newlineMode, NewlineMode.cr);
        expect(mockPrefs.getInt('ui_newline_mode'), NewlineMode.cr.index);
      });
    });

    group('Settings Persistence', () {
      test('restores saved hexDisplay value', () async {
        await mockPrefs.setBool('ui_hex_display', true);
        container.dispose();
        container = createTestContainer(sharedPreferences: mockPrefs);

        final settings = container.read(uiSettingsProvider);
        expect(settings.hexDisplay, true);
      });

      test('restores saved logBufferSize value', () async {
        await mockPrefs.setInt('ui_log_buffer_size', 512);
        container.dispose();
        container = createTestContainer(sharedPreferences: mockPrefs);

        final settings = container.read(uiSettingsProvider);
        expect(settings.logBufferSize, 512);
      });

      test('restores multiple saved settings', () async {
        await mockPrefs.setBool('ui_hex_display', true);
        await mockPrefs.setBool('ui_show_timestamp', false);
        await mockPrefs.setInt('ui_log_buffer_size', 256);
        container.dispose();
        container = createTestContainer(sharedPreferences: mockPrefs);

        final settings = container.read(uiSettingsProvider);
        expect(settings.hexDisplay, true);
        expect(settings.showTimestamp, false);
        expect(settings.logBufferSize, 256);
      });
    });

    group('Independent Settings Updates', () {
      test('updating one setting does not affect others', () {
        final notifier = container.read(uiSettingsProvider.notifier);
        final originalSettings = container.read(uiSettingsProvider);

        notifier.setHexDisplay(true);
        final newSettings = container.read(uiSettingsProvider);

        expect(newSettings.hexDisplay, true); // updated
        expect(newSettings.showTimestamp, originalSettings.showTimestamp); // unchanged
        expect(newSettings.logBufferSize, originalSettings.logBufferSize); // unchanged
      });

      test('multiple sequential updates persist correctly', () {
        final notifier = container.read(uiSettingsProvider.notifier);

        notifier.setHexDisplay(true);
        notifier.setShowTimestamp(false);
        notifier.setLogBufferSize(256);

        final settings = container.read(uiSettingsProvider);
        expect(settings.hexDisplay, true);
        expect(settings.showTimestamp, false);
        expect(settings.logBufferSize, 256);

        // Verify all persisted
        expect(mockPrefs.getBool('ui_hex_display'), true);
        expect(mockPrefs.getBool('ui_show_timestamp'), false);
        expect(mockPrefs.getInt('ui_log_buffer_size'), 256);
      });
    });
  });
}
