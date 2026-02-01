import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/widgets/left_panel/port_selection_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_providers.dart';
import '../../helpers/test_data.dart';

void main() {
  group('PortSelectionWidget', () {
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
      List<String> availablePorts = const ['COM1', 'COM2', 'COM3'],
      String? selectedPort,
    }) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(fakePrefs),
          serialPortServiceProvider.overrideWithValue(mockService),
          availablePortsProvider.overrideWithValue(AsyncData(availablePorts)),
          serialConfigProvider.overrideWith(
            () => TestSerialConfigNotifier(
              selectedPort != null
                  ? serialConfigWithPort(selectedPort)
                  : null,
            ),
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
            body: PortSelectionWidget(),
          ),
        ),
      );
    }

    group('Port Dropdown', () {
      testWidgets('displays available ports correctly', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find DropdownMenu
        expect(find.byType(DropdownMenu<String>), findsOneWidget);

        // Should find selected port in label
        expect(find.text('COM1'), findsOneWidget); // First port is auto-selected

        // Check that dropdown has correct entries
        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.dropdownMenuEntries.length, 3);
      });

      testWidgets('shows loading state when fetching ports', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(fakePrefs),
              availablePortsProvider.overrideWithValue(
                const AsyncLoading(),
              ),
              serialConnectionProvider.overrideWith(
                () => _TestSerialConnectionNotifier(
                  SerialConnection(
                    status: ConnectionStatus.disconnected,
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
                body: PortSelectionWidget(),
              ),
            ),
          ),
        );

        // Should find disabled DropdownMenu
        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.enabled, false);
      });

      testWidgets('shows error state on port fetch failure', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(fakePrefs),
              availablePortsProvider.overrideWithValue(
                const AsyncError('Failed to load ports', StackTrace.empty),
              ),
              serialConnectionProvider.overrideWith(
                () => _TestSerialConnectionNotifier(
                  SerialConnection(
                    status: ConnectionStatus.disconnected,
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
                body: PortSelectionWidget(),
              ),
            ),
          ),
        );

        // Should find disabled DropdownMenu
        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.enabled, false);
      });

      testWidgets('shows empty state when no ports available', (tester) async {
        await tester.pumpWidget(createTestWidget(availablePorts: []));

        // Should find "No ports found" message
        expect(find.text('No ports found'), findsOneWidget);
      });

      testWidgets('displays unavailable port with error style',
          (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            availablePorts: const ['COM1', 'COM2'],
            selectedPort: 'COM3',
          ),
        );

        // Should find error text indicating the port is unavailable
        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.errorText, isNotNull);
        expect(dropdown.errorText, contains('Unavailable'));
      });

      testWidgets('port selection is disabled when connected', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connected,
            selectedPort: 'COM1',
          ),
        );

        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.onSelected, isNull);
      });

      testWidgets('port selection is disabled when busy', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connecting,
            selectedPort: 'COM1',
          ),
        );

        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.onSelected, isNull);
      });
    });

    group('Connect/Disconnect Button', () {
      testWidgets('shows "Open" text when disconnected', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Open'), findsOneWidget);
      });

      testWidgets('shows "Close" text when connected', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connected,
            selectedPort: 'COM1',
          ),
        );

        expect(find.text('Close'), findsOneWidget);
      });

      testWidgets('shows loading indicator during connection',
          (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connecting,
            selectedPort: 'COM1',
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Open'), findsNothing);
      });

      testWidgets('shows loading indicator during disconnection',
          (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.disconnecting,
            selectedPort: 'COM1',
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('button is disabled when busy', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connecting,
            selectedPort: 'COM1',
          ),
        );

        final button = tester.widget<FilledButton>(
          find.byType(FilledButton),
        );
        expect(button.onPressed, isNull);
      });

      testWidgets('button has proper styling when connected', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            connectionStatus: ConnectionStatus.connected,
            selectedPort: 'COM1',
          ),
        );

        final button = tester.widget<FilledButton>(
          find.byType(FilledButton),
        );

        // Button should exist
        expect(button, isNotNull);
      });
    });

    group('User Interactions', () {
      testWidgets('tapping connect button works', (tester) async {
        await tester.pumpWidget(createTestWidget(selectedPort: 'COM1'));

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Button interaction should complete without error
        expect(find.byType(PortSelectionWidget), findsOneWidget);
      });

      testWidgets('attempting to connect to unavailable port shows error',
          (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            availablePorts: const ['COM1', 'COM2'],
            selectedPort: 'COM3',
          ),
        );

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Should show SnackBar
        expect(find.byType(SnackBar), findsOneWidget);
      });
    });

    group('Widget Structure', () {
      testWidgets('renders without errors', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(PortSelectionWidget), findsOneWidget);
        expect(find.byType(DropdownMenu<String>), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
      });

      testWidgets('has proper Row layout', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('dropdown is expanded', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.expandedInsets, EdgeInsets.zero);
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
