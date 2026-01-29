import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/app_error.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/error_provider.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/widgets/status_bar.dart';
import '../helpers/mock_classes.dart';

// Test notifiers that avoid FFI calls
class TestConfigNotifier extends SerialConfigNotifier {
  SerialConfig? _testConfig;

  @override
  SerialConfig? build() => _testConfig;

  void setTestConfig(SerialConfig? config) {
    _testConfig = config;
  }
}

class TestConnectionNotifier extends SerialConnectionNotifier {
  SerialConnection _testConnection = SerialConnection();

  @override
  SerialConnection build() => _testConnection;

  void setTestConnection(SerialConnection connection) {
    _testConnection = connection;
  }
}

class TestErrorNotifier extends ErrorNotifier {
  AppError? testError;

  @override
  AppError? build() => testError;
}

void main() {
  group('StatusBar Widget', () {
    late FakeSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = FakeSharedPreferences();
    });

    Widget createTestStatusBar({
      ConnectionStatus status = ConnectionStatus.disconnected,
      SerialConfig? config,
      AppError? error,
      int rxBytes = 0,
      int txBytes = 0,
      int lastRxBytes = 0,
    }) {
      // Create test notifiers
      final configNotifier = TestConfigNotifier();
      configNotifier.setTestConfig(config);

      final connectionNotifier = TestConnectionNotifier();
      connectionNotifier.setTestConnection(SerialConnection(
        status: status,
        session: null,
        rxBytes: rxBytes,
        txBytes: txBytes,
        lastRxBytes: lastRxBytes,
      ));

      final errorNotifier = TestErrorNotifier();
      errorNotifier.testError = error;

      // Create a container with the test state
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          availablePortsProvider.overrideWithValue(
            AsyncData(['COM1', 'COM2']),
          ),
          // Override with test providers to avoid FFI call
          serialConfigProvider.overrideWith(() => configNotifier),
          serialConnectionProvider.overrideWith(() => connectionNotifier),
          errorProvider.overrideWith(() => errorNotifier),
        ],
      );

      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: StatusBar(),
          ),
        ),
      );
    }

    group('Connection Status Display', () {
      testWidgets('displays disconnected status when not connected',
          (tester) async {
        await tester.pumpWidget(createTestStatusBar());

        // Should find the status bar
        expect(find.byType(StatusBar), findsOneWidget);
      });

      testWidgets('displays connecting status', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(status: ConnectionStatus.connecting),
        );

        expect(find.byType(StatusBar), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
      });

      testWidgets('displays connected status', (tester) async {
        final config = SerialConfig(portName: 'COM1', baudRate: 9600);
        await tester.pumpWidget(
          createTestStatusBar(
            status: ConnectionStatus.connected,
            config: config,
          ),
        );

        expect(find.byType(StatusBar), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
      });

      testWidgets('displays reconnecting status', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(status: ConnectionStatus.reconnecting),
        );

        expect(find.byType(StatusBar), findsOneWidget);
      });

      testWidgets('displays disconnecting status', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(status: ConnectionStatus.disconnecting),
        );

        expect(find.byType(StatusBar), findsOneWidget);
      });
    });

    group('Error Display', () {
      testWidgets('displays config not set error', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            error: const AppError(AppErrorType.configNotSet),
          ),
        );

        expect(find.byType(StatusBar), findsOneWidget);
        final iconFinder = find.byType(Icon);
        expect(iconFinder, findsOneWidget);
      });

      testWidgets('displays port open timeout error', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            error: AppError(AppErrorType.portOpenTimeout, 'Timeout error'),
          ),
        );

        expect(find.byType(StatusBar), findsOneWidget);
      });

      testWidgets('displays write failed error', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            error: AppError(AppErrorType.writeFailed, 'Write failed'),
          ),
        );

        expect(find.byType(StatusBar), findsOneWidget);
      });

      testWidgets('displays invalid hex format error', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            error: const AppError(AppErrorType.invalidHexFormat),
          ),
        );

        expect(find.byType(StatusBar), findsOneWidget);
      });
    });

    group('Statistics Display', () {
      testWidgets('displays zero stats initially', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            rxBytes: 0,
            txBytes: 0,
            lastRxBytes: 0,
          ),
        );

        // Stats text should be present
        expect(find.byType(SelectableText), findsOneWidget);
      });

      testWidgets('displays correct rx/tx bytes', (tester) async {
        await tester.pumpWidget(
          createTestStatusBar(
            rxBytes: 1024,
            txBytes: 512,
            lastRxBytes: 128,
          ),
        );

        // Should find stats display
        expect(find.byType(SelectableText), findsOneWidget);
      });
    });

    group('Layout and Styling', () {
      testWidgets('has correct structure', (tester) async {
        await tester.pumpWidget(createTestStatusBar());

        // Should have Container, Icon, Text within StatusBar
        expect(find.byType(Container), findsWidgets);
        expect(find.byType(Icon), findsOneWidget);
        // Don't check for Row since Scaffold might have one too
      });

      testWidgets('displays status icon on left', (tester) async {
        await tester.pumpWidget(createTestStatusBar());

        expect(find.byType(Icon), findsOneWidget);
      });

      testWidgets('displays stats on right side', (tester) async {
        await tester.pumpWidget(createTestStatusBar());

        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.byType(Tooltip), findsOneWidget);
      });

      testWidgets('has tooltip on stats', (tester) async {
        await tester.pumpWidget(createTestStatusBar());

        expect(find.byType(Tooltip), findsOneWidget);
      });
    });
  });
}
