import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import '../../../helpers/test_providers.dart';
import '../../../helpers/mock_classes.dart';

void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('SerialConfigNotifier', () {
    late ProviderContainer container;
    late FakeSharedPreferences mockPrefs;
    late MockSerialPortService mockService;

    setUp(() {
      mockPrefs = FakeSharedPreferences();
      mockService = MockSerialPortService();
      setupMockSerialPortService(mockService);
      container = createTestContainer(
        sharedPreferences: mockPrefs,
        serialPortService: mockService,
      );
    });

    tearDown(() {
      container.dispose();
    });

    group('Configuration Loading', () {
      test('loads null when no saved port and no ports available', () {
        // No saved port in prefs, and we'll simulate no ports available
        final config = container.read(serialConfigProvider);

        // Should be null since no ports are available
        expect(config, isNull);
      });

      test('restores saved configuration from preferences', () async {
        // Save configuration to prefs
        await mockPrefs.setString('serial_port_name', 'COM3');
        await mockPrefs.setInt('serial_baud_rate', 115200);
        await mockPrefs.setInt('serial_data_bits', 7);
        await mockPrefs.setInt('serial_parity', SerialPortParity.even);
        await mockPrefs.setInt('serial_stop_bits', 2);
        await mockPrefs.setBool('serial_auto_reconnect', false);

        // Create new container to trigger loading
        container.dispose();
        container = createTestContainer(
          sharedPreferences: mockPrefs,
          serialPortService: mockService,
        );

        final config = container.read(serialConfigProvider);

        // Should restore saved config
        expect(config, isNotNull);
        expect(config!.portName, 'COM3');
        expect(config.baudRate, 115200);
        expect(config.dataBits, 7);
        expect(config.parity, SerialPortParity.even);
        expect(config.stopBits, 2);
        expect(config.autoReconnect, false);
      });

      test('uses defaults when saved config is incomplete', () async {
        // Only save port name, other values should use defaults
        await mockPrefs.setString('serial_port_name', 'COM1');

        container.dispose();
        container = createTestContainer(
          sharedPreferences: mockPrefs,
          serialPortService: mockService,
        );

        final config = container.read(serialConfigProvider);

        expect(config, isNotNull);
        expect(config!.portName, 'COM1');
        expect(config.baudRate, 9600); // default
        expect(config.dataBits, 8); // default
        expect(config.parity, SerialPortParity.none); // default
        expect(config.stopBits, 1); // default
        expect(config.autoReconnect, true); // default
      });
    });

    group('Configuration Updates', () {
      test('setPort updates port name and persists to prefs', () {
        container.read(serialConfigProvider.notifier).setPort('COM5');

        final config = container.read(serialConfigProvider);
        expect(config!.portName, 'COM5');
        expect(mockPrefs.getString('serial_port_name'), 'COM5');
      });

      test('setBaudRate updates baud rate and persists to prefs', () {
        container.read(serialConfigProvider.notifier).setBaudRate(115200);

        final config = container.read(serialConfigProvider);
        expect(config!.baudRate, 115200);
        expect(mockPrefs.getInt('serial_baud_rate'), 115200);
      });

      test('setDataBits updates data bits and persists to prefs', () {
        container.read(serialConfigProvider.notifier).setDataBits(7);

        final config = container.read(serialConfigProvider);
        expect(config!.dataBits, 7);
        expect(mockPrefs.getInt('serial_data_bits'), 7);
      });

      test('setParity updates parity and persists to prefs', () {
        container
            .read(serialConfigProvider.notifier)
            .setParity(SerialPortParity.odd);

        final config = container.read(serialConfigProvider);
        expect(config!.parity, SerialPortParity.odd);
        expect(mockPrefs.getInt('serial_parity'), SerialPortParity.odd);
      });

      test('setStopBits updates stop bits and persists to prefs', () {
        container.read(serialConfigProvider.notifier).setStopBits(2);

        final config = container.read(serialConfigProvider);
        expect(config!.stopBits, 2);
        expect(mockPrefs.getInt('serial_stop_bits'), 2);
      });

      test('setAutoReconnect updates auto-reconnect and persists to prefs', () {
        container.read(serialConfigProvider.notifier).setAutoReconnect(false);

        final config = container.read(serialConfigProvider);
        expect(config!.autoReconnect, false);
        expect(mockPrefs.getBool('serial_auto_reconnect'), false);
      });
    });

    group('State Persistence', () {
      test('persists when config is null (creates default config)', () {
        // Initial state might be null
        final notifier = container.read(serialConfigProvider.notifier);

        // Calling setBaudRate when state is null should create a config with defaults
        notifier.setBaudRate(115200);

        // Should have created a config and persisted the baud rate
        expect(mockPrefs.getInt('serial_baud_rate'), 115200);
        // Other defaults should also be persisted
        expect(mockPrefs.getInt('serial_data_bits'), 8);
        expect(mockPrefs.getInt('serial_stop_bits'), 1);
        expect(mockPrefs.getBool('serial_auto_reconnect'), true);
      });

      test('persists all config values after update', () async {
        // Start with a config
        await mockPrefs.setString('serial_port_name', 'COM1');
        container.dispose();
        container = createTestContainer(
          sharedPreferences: mockPrefs,
          serialPortService: mockService,
        );

        // Update multiple fields
        final notifier = container.read(serialConfigProvider.notifier);
        notifier.setBaudRate(57600);
        notifier.setDataBits(7);
        notifier.setStopBits(2);
        notifier.setAutoReconnect(false);

        // Verify all persisted
        expect(mockPrefs.getString('serial_port_name'), 'COM1');
        expect(mockPrefs.getInt('serial_baud_rate'), 57600);
        expect(mockPrefs.getInt('serial_data_bits'), 7);
        expect(mockPrefs.getInt('serial_stop_bits'), 2);
        expect(mockPrefs.getBool('serial_auto_reconnect'), false);
      });
    });

    group('Independent Field Updates', () {
      test('updating baudRate does not affect other fields', () async {
        await mockPrefs.setString('serial_port_name', 'COM1');
        await mockPrefs.setInt('serial_baud_rate', 9600);
        await mockPrefs.setInt('serial_data_bits', 8);
        container.dispose();
        container = createTestContainer(
          sharedPreferences: mockPrefs,
          serialPortService: mockService,
        );

        final notifier = container.read(serialConfigProvider.notifier);
        notifier.setBaudRate(115200);

        final config = container.read(serialConfigProvider);
        expect(config!.portName, 'COM1'); // unchanged
        expect(config.baudRate, 115200); // updated
        expect(config.dataBits, 8); // unchanged
      });

      test('updating port name does not affect other fields', () async {
        await mockPrefs.setString('serial_port_name', 'COM1');
        await mockPrefs.setInt('serial_baud_rate', 9600);
        container.dispose();
        container = createTestContainer(
          sharedPreferences: mockPrefs,
          serialPortService: mockService,
        );

        final notifier = container.read(serialConfigProvider.notifier);
        notifier.setPort('COM10');

        final config = container.read(serialConfigProvider);
        expect(config!.portName, 'COM10'); // updated
        expect(config.baudRate, 9600); // unchanged
      });
    });
  });
}
