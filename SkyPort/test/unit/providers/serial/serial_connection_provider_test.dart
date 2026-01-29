import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skyport/models/app_error.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/providers/serial/data_log_provider.dart';
import 'package:skyport/providers/serial/error_provider.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/services/serial_port_service.dart';
import 'package:skyport/providers/common_providers.dart';
import '../../../helpers/mock_classes.dart';

void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('SerialConnectionNotifier', () {
    late ProviderContainer container;
    late MockSerialPortService mockService;
    late FakeSharedPreferences mockPrefs;
    late FakeSerialPortSession mockSession;

    setUp(() {
      mockService = MockSerialPortService();
      mockPrefs = FakeSharedPreferences();
      mockSession = FakeSerialPortSession();

      // Setup default mock behavior
      setupMockSerialPortService(mockService);

      // Set default config in prefs
      mockPrefs.setString('serial_port_name', 'COM1');
      mockPrefs.setInt('serial_baud_rate', 9600);

      // Create container with all necessary overrides
      container = ProviderContainer(
        overrides: [
          serialPortServiceProvider.overrideWithValue(mockService),
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          availablePortsProvider.overrideWithValue(AsyncData(['COM1', 'COM2'])),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      mockSession.dispose();
    });

    group('Connection Lifecycle', () {
      test('starts in disconnected state', () {
        final connection = container.read(serialConnectionProvider);
        expect(connection.status, ConnectionStatus.disconnected);
      });

      test('transitions to connecting when connect is called', () async {
        final notifier = container.read(serialConnectionProvider.notifier);

        // Setup mock to return session
        when(() => mockService.open(any())).thenAnswer((_) async {
          // Simulate async delay
          await Future.delayed(const Duration(milliseconds: 10));
          return mockSession;
        });

        final future = notifier.connect();

        // Check that state is now connecting
        expect(container.read(serialConnectionProvider).status,
            ConnectionStatus.connecting);

        // Wait for connection to complete
        await future;
      });

      test('transitions to connected on successful open', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);

        // Keep the provider alive during async operations
        final subscription =
            container.listen(serialConnectionProvider, (previous, next) {});

        await notifier.connect();

        final connection = container.read(serialConnectionProvider);
        expect(connection.status, ConnectionStatus.connected);
        expect(connection.session, isNotNull);

        subscription.close();
      });

      test('does nothing if already connecting', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);

        // Start first connection
        final connect1 = notifier.connect();
        // Try to connect again while connecting
        final connect2 = notifier.connect();

        await connect1;
        await connect2;

        // Should only call open once
        verify(() => mockService.open(any())).called(1);
      });

      test('disconnects when already connected', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        expect(container.read(serialConnectionProvider).status,
            ConnectionStatus.connected);

        await notifier.disconnect();

        expect(container.read(serialConnectionProvider).status,
            ConnectionStatus.disconnected);
      });

      test('clears error on connect', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        // Set an error first
        container.read(errorProvider.notifier).setError(AppErrorType.unknown);

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        // Error should be cleared
        expect(container.read(errorProvider), isNull);
      });
    });

    group('Data Reception', () {
      test('updates rxBytes when data is received', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        final subscription =
            container.listen(serialConnectionProvider, (previous, next) {});
        await notifier.connect();

        // Simulate incoming data
        final testData = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
        mockSession.simulateIncomingData(testData);

        // Wait for stream to process
        await Future.delayed(const Duration(milliseconds: 10));

        final connection = container.read(serialConnectionProvider);
        expect(connection.rxBytes, 5);
        expect(connection.lastRxBytes, 5);
        subscription.close();
      });

      test('forwards received data to dataLogProvider', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        final connSubscription =
            container.listen(serialConnectionProvider, (previous, next) {});
        final logSubscription =
            container.listen(dataLogProvider, (previous, next) {});
        await notifier.connect();

        final testData = Uint8List.fromList([0x54, 0x65, 0x73, 0x74]);
        mockSession.simulateIncomingData(testData);

        await Future.delayed(const Duration(milliseconds: 10));

        final logState = container.read(dataLogProvider);
        expect(logState.totalBytes, greaterThan(0));
        connSubscription.close();
        logSubscription.close();
      });

      test('accumulates rxBytes across multiple packets', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        final subscription =
            container.listen(serialConnectionProvider, (previous, next) {});
        await notifier.connect();

        // Send multiple packets
        mockSession.simulateIncomingData(Uint8List.fromList([0x41]));
        await Future.delayed(const Duration(milliseconds: 10));

        mockSession.simulateIncomingData(Uint8List.fromList([0x42, 0x43]));
        await Future.delayed(const Duration(milliseconds: 10));

        final connection = container.read(serialConnectionProvider);
        expect(connection.rxBytes, 3);
        subscription.close();
      });
    });

    group('Data Sending', () {
      test('sends text data when connected', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        await notifier.send('Hello');

        final connection = container.read(serialConnectionProvider);
        expect(connection.txBytes, 5); // 'Hello' is 5 bytes
      });

      test('sends hex data when hexSend enabled', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        // Enable hex send
        final uiSettingsNotifier = container.read(uiSettingsProvider.notifier);
        uiSettingsNotifier.setHexSend(true);

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        await notifier.send('48 65');

        final connection = container.read(serialConnectionProvider);
        expect(connection.txBytes, 2); // 0x48 0x65 is 2 bytes
      });

      test('does nothing when not connected', () async {
        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.send('Hello');

        // Should not modify txBytes since not connected
        final connection = container.read(serialConnectionProvider);
        expect(connection.txBytes, 0);
      });

      test('appends newline when appendNewline is true', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        // Enable newline appending
        final uiSettingsNotifier = container.read(uiSettingsProvider.notifier);
        uiSettingsNotifier.setAppendNewline(true);

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        await notifier.send('Hello');

        final connection = container.read(serialConnectionProvider);
        expect(connection.txBytes, 6); // "Hello\n" is 6 bytes
      });
    });

    group('Error Handling', () {
      test('handles SerialPortOpenTimeoutException', () async {
        when(() => mockService.open(any())).thenThrow(
          SerialPortOpenTimeoutException('Timeout'),
        );

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        final connection = container.read(serialConnectionProvider);
        expect(connection.status, ConnectionStatus.disconnected);

        final error = container.read(errorProvider);
        expect(error?.type, AppErrorType.portOpenTimeout);
      });

      test('handles SerialPortOpenException', () async {
        when(() => mockService.open(any())).thenThrow(
          SerialPortOpenException('Failed to open'),
        );

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        final error = container.read(errorProvider);
        expect(error?.type, AppErrorType.portOpenFailed);
      });

      test('handles invalid hex format', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        // Enable hex send
        final uiSettingsNotifier = container.read(uiSettingsProvider.notifier);
        uiSettingsNotifier.setHexSend(true);

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        await notifier.send('Invalid hex string ZZ');

        final error = container.read(errorProvider);
        expect(error?.type, AppErrorType.invalidHexFormat);
      });
    });

    group('Statistics', () {
      test('resetStats clears all statistics', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        final subscription =
            container.listen(serialConnectionProvider, (previous, next) {});
        await notifier.connect();

        // Simulate some data transfer
        mockSession.simulateIncomingData(Uint8List.fromList([0x41]));
        await Future.delayed(const Duration(milliseconds: 10));

        expect(
            container.read(serialConnectionProvider).rxBytes, greaterThan(0));

        // Reset stats
        notifier.resetStats();

        final connection = container.read(serialConnectionProvider);
        expect(connection.rxBytes, 0);
        expect(connection.txBytes, 0);
        expect(connection.lastRxBytes, 0);
        subscription.close();
      });

      test('txBytes accumulates on multiple sends', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        await notifier.send('ABC');
        await notifier.send('DEF');

        final connection = container.read(serialConnectionProvider);
        expect(connection.txBytes, 6); // 'ABC' (3) + 'DEF' (3) = 6
      });
    });

    group('Auto-reconnect', () {
      test(
          'enters reconnecting state when autoReconnect enabled and connection lost',
          () async {
        // Enable auto-reconnect through the config notifier
        final configNotifier = container.read(serialConfigProvider.notifier);
        final configSubscription =
            container.listen(serialConfigProvider, (previous, next) {});
        configNotifier.setAutoReconnect(true);

        // Verify autoReconnect is set
        final config = container.read(serialConfigProvider);
        expect(config?.autoReconnect, true,
            reason: 'autoReconnect should be true in config');

        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        final connSubscription =
            container.listen(serialConnectionProvider, (previous, next) {});
        await notifier.connect();

        // Verify connected state
        expect(container.read(serialConnectionProvider).status,
            ConnectionStatus.connected);

        // Simulate connection error
        mockSession.simulateError('Connection lost');

        // Wait for error to be processed and reconnection to start
        await Future.delayed(const Duration(milliseconds: 200));

        // Should enter reconnecting state
        final connection = container.read(serialConnectionProvider);
        expect(connection.status, ConnectionStatus.reconnecting,
            reason:
                'Should be in reconnecting state after error with autoReconnect=true');

        configSubscription.close();
        connSubscription.close();
      });

      test('does not reconnect when autoReconnect disabled', () async {
        // Disable auto-reconnect through the config notifier
        final configNotifier = container.read(serialConfigProvider.notifier);
        configNotifier.setAutoReconnect(false);

        when(() => mockService.open(any())).thenAnswer((_) async {
          return mockSession;
        });

        final notifier = container.read(serialConnectionProvider.notifier);
        await notifier.connect();

        // Simulate connection error
        mockSession.simulateError('Connection lost');

        await Future.delayed(const Duration(milliseconds: 10));

        // Should disconnect, not reconnect
        final connection = container.read(serialConnectionProvider);
        expect(connection.status, ConnectionStatus.disconnected);
      });
    });
  });
}
