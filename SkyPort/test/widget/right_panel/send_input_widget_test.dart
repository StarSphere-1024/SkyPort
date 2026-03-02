import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_connection_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';

import '../../helpers/mock_classes.dart';

/// Mock UiSettingsNotifier for testing
class TestUiSettingsNotifier extends UiSettingsNotifier {
  UiSettings _settings;

  TestUiSettingsNotifier(this._settings);

  @override
  UiSettings build() => _settings;

  void updateSettings(UiSettings newSettings) {
    _settings = newSettings;
    state = newSettings;
  }
}

/// Mock SerialConnectionNotifier for testing
class TestSerialConnectionNotifier extends SerialConnectionNotifier {
  SerialConnection _connection;

  TestSerialConnectionNotifier(this._connection);

  @override
  SerialConnection build() => _connection;

  void updateConnection(SerialConnection newConnection) {
    _connection = newConnection;
    state = newConnection;
  }
}

/// Helper to create test widget with all necessary providers
Widget createSendInputTestWidget({
  UiSettings? settings,
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected,
  List<String>? history,
}) {
  final prefs = FakeSharedPreferences();
  if (history != null) {
    prefs.setStringList('send_input_history', history);
  }

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      uiSettingsProvider.overrideWith(
        () => TestUiSettingsNotifier(settings ?? const UiSettings()),
      ),
      serialConnectionProvider.overrideWith(
        () => TestSerialConnectionNotifier(
          SerialConnection(
            status: connectionStatus,
            txBytes: 0,
            rxBytes: 0,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: const Scaffold(
        body: Column(
          children: [SendInputWidget()],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('SendInputWidget - Basic Rendering', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SendInputWidget), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('displays correct label text', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enter data to send'), findsOneWidget);
    });
  });

  group('SendInputWidget - Send Functionality', () {
    testWidgets('send button is clickable when connected and has text',
        (tester) async {
      final prefs = FakeSharedPreferences();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            uiSettingsProvider.overrideWith(
              () => TestUiSettingsNotifier(const UiSettings()),
            ),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.connected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextFormField), 'Hello');
      await tester.pumpAndSettle();

      // Tap send button - should not crash
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // Verify the button was clickable (test completes without error)
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('does not send when disconnected', (tester) async {
      final prefs = FakeSharedPreferences();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            uiSettingsProvider.overrideWith(
              () => TestUiSettingsNotifier(const UiSettings()),
            ),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.disconnected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Hello');
      await tester.pumpAndSettle();

      // Try to tap - should not crash even though disconnected
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // Text should still be there (not sent)
      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('Hello'));
    });
  });

  group('SendInputWidget - Hex Mode', () {
    testWidgets('converts text to hex when switching to hex mode',
        (tester) async {
      final notifier = TestUiSettingsNotifier(const UiSettings(hexSend: false));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider
                .overrideWithValue(FakeSharedPreferences()),
            uiSettingsProvider.overrideWith(() => notifier),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.disconnected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextFormField), 'AB');
      await tester.pumpAndSettle();

      // Switch to hex mode by updating the notifier
      notifier.updateSettings(const UiSettings(hexSend: true));
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      // "AB" in hex is "41 42"
      expect(controller?.text, equals('41 42'));
    });

    testWidgets('converts hex to text when switching to text mode',
        (tester) async {
      final notifier = TestUiSettingsNotifier(const UiSettings(hexSend: true));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider
                .overrideWithValue(FakeSharedPreferences()),
            uiSettingsProvider.overrideWith(() => notifier),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.disconnected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter hex
      await tester.enterText(find.byType(TextFormField), '41 42');
      await tester.pumpAndSettle();

      // Switch to text mode
      notifier.updateSettings(const UiSettings(hexSend: false));
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('AB'));
    });

    testWidgets('validates hex input - even length required', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      // Enter odd-length hex
      await tester.enterText(find.byType(TextFormField), 'ABC');
      await tester.pumpAndSettle();

      expect(find.text('Hex string must have an even length.'), findsOneWidget);
    });

    testWidgets('validates hex input - valid characters', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      // Enter invalid hex characters
      await tester.enterText(find.byType(TextFormField), 'XYZ123');
      await tester.pumpAndSettle();

      expect(find.text('Invalid characters. Use 0-9, A-F.'), findsOneWidget);
    });

    testWidgets('accepts uppercase and lowercase hex', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'aBcD12');
      await tester.pumpAndSettle();

      // Should not show error
      expect(find.text('Invalid characters. Use 0-9, A-F.'), findsNothing);
      expect(find.text('Hex string must have an even length.'), findsNothing);
    });

    testWidgets('ignores spaces in hex input', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '41 42 43');
      await tester.pumpAndSettle();

      // Should be valid
      expect(find.text('Invalid characters. Use 0-9, A-F.'), findsNothing);
    });

    testWidgets('error disappears when input is corrected', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      // Enter invalid hex
      await tester.enterText(find.byType(TextFormField), 'ABC');
      await tester.pumpAndSettle();
      expect(find.text('Hex string must have an even length.'), findsOneWidget);

      // Fix the input
      await tester.enterText(find.byType(TextFormField), 'ABCD');
      await tester.pumpAndSettle();
      expect(find.text('Hex string must have an even length.'), findsNothing);
    });
  });

  group('SendInputWidget - History', () {
    testWidgets('saves sent messages to history', (tester) async {
      final prefs = FakeSharedPreferences();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            uiSettingsProvider.overrideWith(
              () => TestUiSettingsNotifier(const UiSettings()),
            ),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.connected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Send a message
      await tester.enterText(find.byType(TextFormField), 'Test message');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // Check history was saved
      final history = prefs.getStringList('send_input_history');
      expect(history, contains('Test message'));
    });

    testWidgets('navigates history with up arrow key', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
        history: ['First message', 'Second message', 'Third message'],
      ));
      await tester.pumpAndSettle();

      // Focus the text field
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();

      // Press up arrow
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('Third message'));
    });

    testWidgets('navigates history with down arrow key', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
        history: ['First message', 'Second message', 'Third message'],
      ));
      await tester.pumpAndSettle();

      // Focus the text field
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();

      // Press up arrow to get history
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // Press down arrow to go back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      // Should return to original (empty) state
      expect(controller?.text, isEmpty);
    });

    testWidgets('moves recently sent message to end of history',
        (tester) async {
      final prefs = FakeSharedPreferences()
        ..setStringList('send_input_history', [
          'First message',
          'Existing message',
        ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            uiSettingsProvider.overrideWith(
              () => TestUiSettingsNotifier(const UiSettings()),
            ),
            serialConnectionProvider.overrideWith(
              () => TestSerialConnectionNotifier(
                SerialConnection(
                  status: ConnectionStatus.connected,
                  txBytes: 0,
                  rxBytes: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const Scaffold(
              body: SendInputWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Send existing message again
      await tester.enterText(find.byType(TextFormField), 'Existing message');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      final history = prefs.getStringList('send_input_history');
      expect(history?.last, equals('Existing message'));
      expect(history?.where((s) => s == 'Existing message').length, equals(1));
    });

    testWidgets('handles empty history gracefully', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
        history: [],
      ));
      await tester.pumpAndSettle();

      // Try to navigate history with empty list
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('history navigation resets to original input', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
        history: ['History 1', 'History 2'],
      ));
      await tester.pumpAndSettle();

      // Start typing
      await tester.enterText(find.byType(TextFormField), 'New text');
      await tester.pumpAndSettle();

      // Navigate up (save current and show history)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // Navigate down to return to original
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('New text'));
    });
  });

  group('SendInputWidget - Input Validation', () {
    testWidgets('text mode allows any characters', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'Special chars: @#%^&*()!',
      );
      await tester.pumpAndSettle();

      // Should not show validation error
      expect(find.text('Invalid characters. Use 0-9, A-F.'), findsNothing);
    });

    testWidgets('hex mode only allows 0-9a-fA-F', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'GHI');
      await tester.pumpAndSettle();

      expect(find.text('Invalid characters. Use 0-9, A-F.'), findsOneWidget);
    });

    testWidgets('validation state updates in real-time', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      // Start with invalid input
      await tester.enterText(find.byType(TextFormField), 'ABC');
      await tester.pumpAndSettle();
      expect(find.text('Hex string must have an even length.'), findsOneWidget);

      // Add one more character to make it valid
      await tester.enterText(find.byType(TextFormField), 'ABCD');
      await tester.pumpAndSettle();
      expect(find.text('Hex string must have an even length.'), findsNothing);
    });
  });

  group('SendInputWidget - Focus & Shortcuts', () {
    testWidgets('focuses text field on tap', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();

      // TextField should be focusable
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('cursor positioned at end after text entry', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Test text');
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.selection.baseOffset, equals(9));
    });

    testWidgets('focus lost state is preserved', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget());
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextFormField), 'Persistent text');
      await tester.pumpAndSettle();

      // Tap elsewhere to remove focus
      await tester.tap(find.byType(Scaffold));
      await tester.pumpAndSettle();

      // Text should still be there
      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('Persistent text'));
    });
  });

  group('SendInputWidget - Edge Cases', () {
    testWidgets('handles very long input', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      final longText = 'A' * 1000;
      await tester.enterText(find.byType(TextFormField), longText);
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text.length, equals(1000));
    });

    testWidgets('handles unicode characters', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        connectionStatus: ConnectionStatus.connected,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Hello 世界 🌍');
      await tester.pumpAndSettle();

      final finder = find.byType(TextFormField);
      final controller =
          (tester.firstWidget(finder) as TextFormField).controller;
      expect(controller?.text, equals('Hello 世界 🌍'));
    });

    testWidgets('hex conversion handles empty input', (tester) async {
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: false),
      ));
      await tester.pumpAndSettle();

      // Switch to hex mode with empty input
      await tester.pumpWidget(createSendInputTestWidget(
        settings: const UiSettings(hexSend: true),
      ));
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });
}
