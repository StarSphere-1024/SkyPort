import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/widgets/left_panel/send_settings_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_providers.dart';

void main() {
  group('SendSettingsWidget', () {
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
            body: SendSettingsWidget(),
          ),
        ),
      );
    }

    group('Settings Labels', () {
      testWidgets('renders all setting labels', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should find key labels
        expect(find.textContaining('Hex'), findsOneWidget);
        expect(find.textContaining('Auto'), findsOneWidget);
        expect(find.textContaining('Newline'), findsOneWidget);
      });
    });

    group('Widget Structure', () {
      testWidgets('renders without errors', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(SendSettingsWidget), findsOneWidget);
        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('has switches and input fields', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(Switch), findsWidgets);
        expect(find.byType(TextField), findsWidgets); // Multiple text fields
      });
    });

    group('User Interactions', () {
      testWidgets('can interact with switches', (tester) async {
        await tester.pumpWidget(createTestWidget());

        final switches = find.byType(Switch);
        expect(switches, findsWidgets);

        await tester.tap(switches.first);
        await tester.pumpAndSettle();

        expect(find.byType(SendSettingsWidget), findsOneWidget);
      });

      testWidgets('can enter text in auto-send interval field',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        final textFields = find.byType(TextField);
        expect(textFields, findsWidgets);

        // Tap the first TextField (auto-send interval)
        await tester.tap(textFields.first);
        await tester.pumpAndSettle();

        await tester.enterText(textFields.first, '5');
        await tester.pumpAndSettle();

        expect(find.text('5'), findsOneWidget);
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
