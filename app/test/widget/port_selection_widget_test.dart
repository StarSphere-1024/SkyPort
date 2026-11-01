import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/widgets/left_panel/port_selection_widget.dart';

class _PortController extends UiController {
  int connects = 0;
  int disconnects = 0;
  String selectedPort = '/dev/ttyUSB0';

  UiState _snapshot({
    UiConnection connection = UiConnection.disconnected,
    List<UiPort> ports = const [],
  }) => UiState(
    sequence: 0,
    connection: connection,
    portName: selectedPort,
    baudRate: 115200,
    dataBits: 8,
    parity: UiParity.none,
    flowControl: UiFlowControl.none,
    stopBits: 1,
    autoReconnect: false,
    hexSend: false,
    newline: UiNewline.none,
    autoSendEnabled: false,
    autoSendIntervalMs: 1000,
    logCapacityBytes: 1024,
    sendHistory: const [],
    autoSendInput: '',
    ports: ports,
    rxBytes: 0,
    txBytes: 0,
    lastRxBytes: 0,
    error: null,
    logs: const LogState(),
    trimmedBytes: 0,
    trimmedRecords: 0,
    logIncomplete: false,
  );

  @override
  UiState build() => _snapshot(ports: const [UiPort(portName: '/dev/ttyS0')]);

  void updatePorts(List<UiPort> ports) =>
      state = _snapshot(connection: state.connection, ports: ports);

  void updateConnection(UiConnection connection) =>
      state = _snapshot(connection: connection, ports: state.ports);

  @override
  Future<void> setPort(String value) async {
    selectedPort = value;
    state = _snapshot(connection: state.connection, ports: state.ports);
  }

  @override
  Future<void> connect() async {
    connects++;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

void main() {
  testWidgets(
    'selector excludes unavailable target, disables open, restores on plug',
    (tester) async {
      final container = ProviderContainer(
        overrides: [uiControllerProvider.overrideWith(_PortController.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: PortSelectionWidget()),
          ),
        ),
      );

      DropdownButton<String> selector() =>
          tester.widget(find.byType(DropdownButton<String>));
      FilledButton action() => tester.widget(find.byType(FilledButton));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(PortSelectionWidget)),
      );
      expect(selector().items!.map((entry) => entry.value), ['/dev/ttyS0']);
      expect(find.text('${l10n.unavailable}: /dev/ttyUSB0'), findsOneWidget);
      expect(action().onPressed, isNull);

      final controller =
          container.read(uiControllerProvider.notifier) as _PortController;
      controller.updatePorts(const [
        UiPort(portName: '/dev/ttyS0'),
        UiPort(portName: '/dev/ttyUSB0'),
      ]);
      await tester.pump();

      expect(selector().items!.map((entry) => entry.value), [
        '/dev/ttyS0',
        '/dev/ttyUSB0',
      ]);
      expect(find.text('${l10n.unavailable}: /dev/ttyUSB0'), findsNothing);
      expect(selector().value, '/dev/ttyUSB0');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('/dev/ttyS0').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      expect(controller.connects, 1);
      controller.updatePorts(const [UiPort(portName: '/dev/ttyS0')]);
      await tester.pump();
      expect(selector().items!.map((entry) => entry.value), ['/dev/ttyS0']);
      expect(action().onPressed, isNull);

      controller.updatePorts([]);
      await tester.pump();
      expect(find.text(l10n.noPortsFound), findsOneWidget);
      expect(find.textContaining('/dev/ttyUSB0'), findsWidgets);
      controller.updateConnection(UiConnection.reconnecting);
      await tester.pump();
      expect(
        find.textContaining('${l10n.reconnecting}: /dev/ttyUSB0'),
        findsOneWidget,
      );
      expect(action().onPressed, isNotNull);
      await tester.tap(find.byType(FilledButton));
      expect(controller.disconnects, 1);
    },
  );

  testWidgets(
    'device metadata distinguishes identical products at narrow width',
    (tester) async {
      final container = ProviderContainer(
        overrides: [uiControllerProvider.overrideWith(_PortController.new)],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(uiControllerProvider.notifier) as _PortController;
      controller.updatePorts(const [
        UiPort(
          portName: '/dev/ttyUSB0',
          product: 'CP2102 USB to UART Bridge Controller',
          manufacturer: 'Silicon Labs',
          vid: 0x10c4,
          pid: 0xea60,
          serialNumber: 'DEVICE-A',
        ),
        UiPort(
          portName: '/dev/ttyUSB1',
          product: 'CP2102 USB to UART Bridge Controller',
          serialNumber: 'DEVICE-B',
        ),
        UiPort(portName: '/dev/ttyS0'),
      ]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(width: 320, child: PortSelectionWidget()),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Silicon Labs · VID:PID 10C4:EA60').hitTestable(),
        findsOneWidget,
      );
      final secondDevice = find
          .text('/dev/ttyUSB1 · CP2102 USB to UART Bridge Controller')
          .hitTestable();
      expect(secondDevice, findsOneWidget);
      await tester.tap(secondDevice);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        '/dev/ttyUSB1',
      );
      expect(
        find.byTooltip(
          '/dev/ttyUSB1 · CP2102 USB to UART Bridge Controller\nSerial: DEVICE-B',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
