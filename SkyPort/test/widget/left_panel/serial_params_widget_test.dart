import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/widgets/left_panel/serial_params_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_data.dart';
import '../../helpers/test_providers.dart';

void main() {
  group('SerialParamsWidget', () {
    late MockSerialPortService mockService;
    late FakeSharedPreferences fakePrefs;

    setUpAll(() {
      registerFallbackValues();
    });

    setUp(() {
      mockService = MockSerialPortService();
      fakePrefs = FakeSharedPreferences();
      setupMockSerialPortService(mockService);
    });

    Widget createTestWidget({
      ConnectionStatus connectionStatus = ConnectionStatus.disconnected,
      SerialConfig? config,
    }) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(fakePrefs),
          serialPortServiceProvider.overrideWithValue(mockService),
          availablePortsProvider.overrideWithValue(AsyncData(['COM1'])),
          serialConfigProvider.overrideWith(
            () => TestSerialConfigNotifier(config ?? defaultSerialConfig()),
          ),
          serialConnectionProvider.overrideWith(
            () => _TestSerialConnectionNotifier(
              SerialConnection(
                status: connectionStatus,
                txBytes: 0,
                rxBytes: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en', 'US'),
          home: Scaffold(
            body: SerialParamsWidget(),
          ),
        ),
      );
    }

    group('Baud Rate Dropdown', () {
      testWidgets('displays baud rate dropdown', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find baud rate dropdown
        expect(find.byType(DropdownMenu<int>), findsWidgets);

        // Should find baud rate label
        expect(find.text('Baud Rate'), findsOneWidget);
      });

      testWidgets('contains standard baud rates', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Find all dropdowns and check entries
        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        // First dropdown should be baud rate
        final baudDropdown = dropdowns.first;
        expect(baudDropdown.dropdownMenuEntries.length, 11); // 11 standard rates

        // Check some key values
        final entries = baudDropdown.dropdownMenuEntries;
        final labels = entries.map((e) => e.label).toList();

        expect(labels, contains('1200'));
        expect(labels, contains('9600'));
        expect(labels, contains('115200'));
        expect(labels, contains('921600'));
      });

      testWidgets('shows current baud rate', (tester) async {
        const testBaud = 115200;
        await tester.pumpWidget(
          createTestWidget(
            config: serialConfigWithBaudRate(testBaud),
          ),
        );

        // Should find the baud rate in the UI
        expect(find.text('$testBaud'), findsOneWidget);
      });

      testWidgets('is disabled when connected', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connected,
          ),
        );

        // All dropdowns should have null onSelected
        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        for (final dropdown in dropdowns) {
          expect(dropdown.onSelected, isNull);
        }
      });

      testWidgets('is disabled when busy', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connecting,
          ),
        );

        // All dropdowns should have null onSelected
        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        for (final dropdown in dropdowns) {
          expect(dropdown.onSelected, isNull);
        }
      });
    });

    group('Data Bits Dropdown', () {
      testWidgets('displays data bits dropdown', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find data bits label
        expect(find.text('Data Bits'), findsOneWidget);
      });

      testWidgets('contains valid data bits values', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        // Find data bits dropdown (second one)
        final dataBitsDropdown = dropdowns.elementAt(1);
        final labels = dataBitsDropdown.dropdownMenuEntries.map((e) => e.label);

        expect(labels, containsAll(['8', '7', '6', '5']));
      });

      testWidgets('shows current data bits', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Default is 8 data bits
        expect(find.text('8'), findsOneWidget);
      });
    });

    group('Parity Dropdown', () {
      testWidgets('displays parity dropdown', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find parity label
        expect(find.text('Parity'), findsOneWidget);
      });

      testWidgets('contains parity options', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        // Find parity dropdown (third one)
        final parityDropdown = dropdowns.elementAt(2);
        final labels = parityDropdown.dropdownMenuEntries.map((e) => e.label);

        expect(labels, containsAll(['None', 'Odd', 'Even']));
      });

      testWidgets('shows current parity', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Default is None (0)
        expect(find.text('None'), findsOneWidget);
      });
    });

    group('Stop Bits Dropdown', () {
      testWidgets('displays stop bits dropdown', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find stop bits label
        expect(find.text('Stop Bits'), findsOneWidget);
      });

      testWidgets('contains valid stop bits values', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        // Find stop bits dropdown (fourth one)
        final stopBitsDropdown = dropdowns.elementAt(3);
        final labels = stopBitsDropdown.dropdownMenuEntries.map((e) => e.label);

        expect(labels, containsAll(['1', '2']));
      });

      testWidgets('shows current stop bits', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Default is 1 stop bit
        expect(find.text('1'), findsOneWidget);
      });
    });

    group('Widget Layout', () {
      testWidgets('renders without errors', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(SerialParamsWidget), findsOneWidget);
        expect(find.byType(DropdownMenu<int>), findsWidgets); // Multiple dropdowns
      });

      testWidgets('has proper Column layout', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('has proper Row layout for paired controls',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should have 2 rows (baud+data bits, parity+stop bits)
        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('all dropdowns are expanded', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final dropdowns = tester.widgetList<DropdownMenu<int>>(
          find.byType(DropdownMenu<int>),
        );

        for (final dropdown in dropdowns) {
          expect(dropdown.expandedInsets, EdgeInsets.zero);
        }
      });
    });

    group('Configuration Updates', () {
      testWidgets('initial values match config defaults', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Default config: 9600 baud, 8 data bits, None parity, 1 stop bit
        expect(find.text('9600'), findsOneWidget);
        expect(find.text('8'), findsOneWidget);
        expect(find.text('None'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
      });

      testWidgets('displays custom config values', (tester) async {
        final customConfig = SerialConfig(
          portName: 'COM1',
          baudRate: 115200,
          dataBits: 7,
          parity: 1, // Odd
          stopBits: 2,
          autoReconnect: false,
        );

        await tester.pumpWidget(createTestWidget(config: customConfig));

        expect(find.text('115200'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('Odd'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      });
    });
  });
}

/// Test implementation of SerialConnectionNotifier
class _TestSerialConnectionNotifier extends SerialConnectionNotifier {
  final SerialConnection _connection;

  _TestSerialConnectionNotifier(this._connection);

  @override
  SerialConnection build() => _connection;
}
