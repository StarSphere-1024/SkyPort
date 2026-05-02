import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';

import '../../helpers/mock_classes.dart';

class TestUiSettingsNotifier extends UiSettingsNotifier {
  TestUiSettingsNotifier(this._settings);

  UiSettings _settings;

  @override
  UiSettings build() => _settings;

  void updateSettings(UiSettings next) {
    _settings = next;
    state = next;
  }
}

void main() {
  setUpAll(registerFallbackValues);

  Widget createSendInputTestWidget({
    required FakeSharedPreferences prefs,
    required MockSerialPortService mockService,
    UiSettings? settings,
  }) {
    final uiNotifier = TestUiSettingsNotifier(settings ?? const UiSettings());

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serialPortServiceProvider.overrideWithValue(mockService),
        uiSettingsProvider.overrideWith(() => uiNotifier),
      ],
      child: MaterialApp(
        theme: ThemeData(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: const Scaffold(body: SendInputWidget()),
      ),
    );
  }

  group('SendInputWidget', () {
    late FakeSharedPreferences prefs;
    late MockSerialPortService mockService;

    setUp(() {
      prefs = FakeSharedPreferences()..setString('serial_port_name', 'COM1');
      mockService = MockSerialPortService();
      setupMockSerialPortService(mockService);
    });

    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SendInputWidget), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('hex validation errors appear', (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          mockService: mockService,
          settings: const UiSettings(hexSend: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'ABC');
      await tester.pumpAndSettle();

      expect(find.text('Hex string must have an even length.'), findsOneWidget);
    });

    testWidgets('history navigation works', (tester) async {
      prefs.setStringList('send_input_history', ['One', 'Two']);

      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          mockService: mockService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Two');
    });
  });
}
