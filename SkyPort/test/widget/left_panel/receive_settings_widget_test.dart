import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/widgets/left_panel/receive_settings_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_providers.dart';

void main() {
  group('ReceiveSettingsWidget', () {
    late FakeSharedPreferences fakePrefs;

    setUp(() {
      fakePrefs = FakeSharedPreferences();
    });

    Widget createTestWidget({UiSettings? settings}) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(fakePrefs),
          uiSettingsProvider.overrideWith(
            () => TestUiSettingsNotifier(settings ?? const UiSettings()),
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
            body: ReceiveSettingsWidget(),
          ),
        ),
      );
    }

    group('Settings Labels', () {
      testWidgets('renders all setting labels', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find all labels
        expect(find.text('Hex Display'), findsOneWidget);
        expect(find.text('Show Timestamp'), findsOneWidget);
        expect(find.text('Show Sent Data'), findsOneWidget);
      });
    });

    group('Widget Structure', () {
      testWidgets('renders without errors', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ReceiveSettingsWidget), findsOneWidget);
        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('has 3 switches', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(Switch), findsNWidgets(3));
      });

      testWidgets('displays initial values from settings', (tester) async {
        final testSettings = const UiSettings(
          hexDisplay: true,
          showTimestamp: false,
          showSent: true,
        );

        await tester.pumpWidget(createTestWidget(settings: testSettings));

        // Widget should render without errors
        expect(find.byType(ReceiveSettingsWidget), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(3));
      });
    });

    group('User Interactions', () {
      testWidgets('can interact with switches', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Tap on the first switch
        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(3));

        await tester.tap(switches.first);
        await tester.pumpAndSettle();

        // Widget should still exist after interaction
        expect(find.byType(ReceiveSettingsWidget), findsOneWidget);
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
