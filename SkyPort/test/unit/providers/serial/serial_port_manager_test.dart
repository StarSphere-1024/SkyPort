import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/services/serial_port_service.dart';

import '../../../helpers/mock_classes.dart';

void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('SerialPortManager', () {
    late ProviderContainer container;
    late MockSerialPortService mockService;
    late FakeSharedPreferences mockPrefs;

    setUp(() {
      mockService = MockSerialPortService();
      mockPrefs = FakeSharedPreferences();

      setupMockSerialPortService(mockService);

      mockPrefs.setString('serial_port_name', 'COM1');
      mockPrefs.setInt('serial_baud_rate', 9600);

      container = ProviderContainer(
        overrides: [
          serialPortServiceProvider.overrideWithValue(mockService),
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    group('Reconciliation Loop', () {
      test('rapid config changes converge to the final baud rate', () async {
        final openedConfigs = <SerialConfig>[];
        when(() => mockService.open(any())).thenAnswer((invocation) async {
          final config = invocation.positionalArguments.first as SerialConfig;
          openedConfigs.add(config);
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);

        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        var state = container.read(serialPortManagerProvider);
        expect(state.connection.appliedConfig?.baudRate, 9600);
        expect(openedConfigs, hasLength(1));

        manager.setBaudRate(19200);
        manager.setBaudRate(38400);
        manager.setBaudRate(115200);

        await Future.delayed(const Duration(milliseconds: 500));

        state = container.read(serialPortManagerProvider);
        expect(state.connection.appliedConfig?.baudRate, 115200);
        expect(state.connection.state, ConnectionState.connected);
        expect(state.isReconciling, false);
        expect(openedConfigs.first.baudRate, 9600);
        expect(openedConfigs.last.baudRate, 115200);
        expect(openedConfigs.length, greaterThanOrEqualTo(2));
      });

      test('failed reconfiguration falls back to disconnected with error',
          () async {
        when(() => mockService.open(any())).thenAnswer((invocation) async {
          final config = invocation.positionalArguments.first as SerialConfig;
          if (config.baudRate == 999999) {
            throw SerialPortOpenException('Invalid baud rate');
          }
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);

        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        var state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.connected);

        manager.setBaudRate(999999);
        await Future.delayed(const Duration(milliseconds: 450));

        state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.disconnected);
        expect(state.connection.errorMessage, isNotNull);
        expect(state.connection.appliedConfig, isNull);
        expect(state.isReconciling, false);
      });

      test('successful connect stores the applied config', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        final targetConfig = SerialConfig(
          portName: 'COM1',
          baudRate: 115200,
          dataBits: 7,
          parity: 2,
          stopBits: 2,
        );

        manager.updateConfig(targetConfig);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.appliedConfig, isNotNull);
        expect(state.connection.appliedConfig!.baudRate, 115200);
        expect(state.connection.appliedConfig!.dataBits, 7);
        expect(state.connection.appliedConfig!.parity, 2);
        expect(state.connection.appliedConfig!.stopBits, 2);
        expect(state.isInSync, true);
      });

      test(
          'changing only the port triggers reconciliation and updates appliedConfig',
          () async {
        final openedConfigs = <SerialConfig>[];
        when(() => mockService.open(any())).thenAnswer((invocation) async {
          final config = invocation.positionalArguments.first as SerialConfig;
          openedConfigs.add(config);
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);

        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 80));

        manager.setPortName('COM2');
        await Future.delayed(const Duration(milliseconds: 450));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.connected);
        expect(state.connection.appliedConfig?.portName, 'COM2');
        expect(state.isInSync, true);
        expect(openedConfigs.map((c) => c.portName),
            containsAll(['COM1', 'COM2']));
      });

      test('disconnect during connect discards stale open result', () async {
        final pendingOpen = Completer<SerialPortSessionInterface>();
        when(() => mockService.open(any()))
            .thenAnswer((_) => pendingOpen.future);

        final manager = container.read(serialPortManagerProvider.notifier);

        unawaited(manager.connect());
        await Future.delayed(const Duration(milliseconds: 20));
        await manager.disconnect();

        pendingOpen.complete(FakeSerialPortSession());
        await Future.delayed(const Duration(milliseconds: 120));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.disconnected);
        expect(state.connection.appliedConfig, isNull);
      });

      test('reconciliation state is exposed through isReconciling', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);

        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        manager.setBaudRate(115200);

        var state = container.read(serialPortManagerProvider);
        expect(
          state.isReconciling ||
              state.connection.state == ConnectionState.reconfiguring,
          true,
        );

        await Future.delayed(const Duration(milliseconds: 550));

        state = container.read(serialPortManagerProvider);
        expect(state.isReconciling, false);
        expect(state.connection.state, ConnectionState.connected);
      });

      test('connection loss enters reconnecting when autoReconnect is enabled',
          () async {
        final session = FakeSerialPortSession();
        var ports = <String>['COM1'];
        when(() => mockService.getAvailablePorts())
            .thenAnswer((_) async => ports);
        when(() => mockService.open(any())).thenAnswer((_) async => session);

        final manager = container.read(serialPortManagerProvider.notifier);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 250));

        ports = <String>[];
        session.simulateError('Connection lost');
        await Future.delayed(const Duration(milliseconds: 250));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.reconnecting);
        expect(state.connection.appliedConfig, isNull);
        expect(state.connection.errorMessage, contains('Connection lost'));
      });

      test('reconnecting auto-connects after port becomes available again',
          () async {
        final initialSession = FakeSerialPortSession();
        final recoveredSession = FakeSerialPortSession();
        var openCount = 0;
        var ports = <String>['COM1'];

        when(() => mockService.getAvailablePorts())
            .thenAnswer((_) async => ports);
        when(() => mockService.open(any())).thenAnswer((_) async {
          openCount += 1;
          return openCount == 1 ? initialSession : recoveredSession;
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 80));

        ports = <String>[];
        initialSession.simulateError('Cable unplugged');
        await Future.delayed(const Duration(milliseconds: 320));

        var state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.reconnecting);

        ports = <String>['COM1'];
        await Future.delayed(const Duration(milliseconds: 700));

        state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.connected);
        expect(state.connection.appliedConfig?.portName, 'COM1');
        expect(openCount, greaterThanOrEqualTo(2));
      });
    });

    group('Configuration Operations', () {
      test('updateConfig updates targetConfig immediately', () {
        final manager = container.read(serialPortManagerProvider.notifier);
        final newConfig = SerialConfig(
          portName: 'COM1',
          baudRate: 115200,
          dataBits: 8,
          parity: 0,
          stopBits: 1,
        );

        manager.updateConfig(newConfig);

        final state = container.read(serialPortManagerProvider);
        expect(state.targetConfig.baudRate, 115200);
        expect(state.targetConfig.portName, 'COM1');
      });

      test('individual setters update the target config', () {
        final manager = container.read(serialPortManagerProvider.notifier);

        manager.setBaudRate(57600);
        var state = container.read(serialPortManagerProvider);
        expect(state.targetConfig.baudRate, 57600);

        manager.setDataBits(7);
        state = container.read(serialPortManagerProvider);
        expect(state.targetConfig.dataBits, 7);

        manager.setParity(1);
        state = container.read(serialPortManagerProvider);
        expect(state.targetConfig.parity, 1);

        manager.setStopBits(2);
        state = container.read(serialPortManagerProvider);
        expect(state.targetConfig.stopBits, 2);
      });

      test('config changes are persisted to SharedPreferences', () {
        final manager = container.read(serialPortManagerProvider.notifier);

        manager.setBaudRate(115200);

        expect(mockPrefs.getInt('serial_baud_rate'), 115200);
      });
    });

    group('Connection Lifecycle', () {
      test('initial state is disconnected', () {
        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.disconnected);
        expect(state.connection.appliedConfig, isNull);
      });

      test('connect transitions to connected on success', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.connected);
      });

      test('disconnect clears appliedConfig and returns to disconnected',
          () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        await manager.disconnect();
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.state, ConnectionState.disconnected);
        expect(state.connection.appliedConfig, isNull);
      });

      test('isBusy is true while connecting', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);

        unawaited(manager.connect());

        var state = container.read(serialPortManagerProvider);
        expect(state.isBusy, true);

        await Future.delayed(const Duration(milliseconds: 150));

        state = container.read(serialPortManagerProvider);
        expect(state.isBusy, false);
      });
    });

    group('State Computed Properties', () {
      test('displayBaudRate uses targetConfig when disconnected', () {
        final manager = container.read(serialPortManagerProvider.notifier);
        manager.setBaudRate(115200);

        final state = container.read(serialPortManagerProvider);
        expect(state.displayBaudRate, 115200);
      });

      test('displayBaudRate uses appliedConfig when connected', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        manager.setBaudRate(9600);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(serialPortManagerProvider);
        expect(state.connection.appliedConfig?.baudRate, 9600);
        expect(state.displayBaudRate, 9600);
      });

      test('isInSync is true when target matches applied config', () async {
        when(() => mockService.open(any())).thenAnswer((_) async {
          return FakeSerialPortSession();
        });

        final manager = container.read(serialPortManagerProvider.notifier);
        await manager.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(serialPortManagerProvider);
        expect(state.isInSync, true);
      });
    });
  });
}
