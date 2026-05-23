import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/models/serial_port_state.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';

import '../../helpers/mock_classes.dart';

Future<void> pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class TestSerialPortManager extends SerialPortManager {
  final sentData = <String>[];

  @override
  SerialPortState build() {
    return SerialPortState(
      targetConfig: SerialConfig(portName: 'COM1'),
      connection: const ConnectionStatus(),
      availablePorts: const ['COM1'],
    );
  }

  void setConnectionState(ConnectionState connectionState) {
    state = state.copyWith(
      connection: state.connection.copyWith(state: connectionState),
    );
  }

  @override
  Future<void> send(String data) async {
    sentData.add(data);
    state = state.copyWith(
      connection: state.connection.copyWith(
        txBytes: state.connection.txBytes + data.length,
      ),
    );
  }
}

void main() {
  setUpAll(registerFallbackValues);

  Widget createSendInputTestWidget({
    required FakeSharedPreferences prefs,
    required ProviderContainer container,
    UiSettings? settings,
  }) {
    if (settings != null) {
      prefs
        ..setBool('ui_hex_send', settings.hexSend)
        ..setBool('ui_auto_send_enabled', settings.autoSendEnabled)
        ..setInt('ui_auto_send_interval_ms', settings.autoSendIntervalMs);
    }

    return UncontrolledProviderScope(
      container: container,
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
    late ProviderContainer container;
    late TestSerialPortManager serialManager;

    setUp(() {
      prefs = FakeSharedPreferences()..setString('serial_port_name', 'COM1');
      serialManager = TestSerialPortManager();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serialPortManagerProvider.overrideWith(() => serialManager),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
        ),
      );
      await pumpFrame(tester);

      expect(find.byType(SendInputWidget), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('hex validation errors appear', (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
          settings: const UiSettings(hexSend: true),
        ),
      );
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), 'ABC');
      await pumpFrame(tester);

      expect(find.text('Hex string must have an even length.'), findsOneWidget);
    });

    testWidgets('history navigation works', (tester) async {
      prefs.setStringList('send_input_history', ['One', 'Two']);

      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
        ),
      );
      await pumpFrame(tester);

      await tester.tap(find.byType(TextFormField));
      await pumpFrame(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await pumpFrame(tester);

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Two');
    });

    testWidgets('send button writes data and stores history', (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
        ),
      );
      await pumpFrame(tester);

      serialManager.setConnectionState(ConnectionState.connected);
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), 'Hello');
      await pumpFrame(tester);
      await tester.tap(find.byType(FilledButton));
      await pumpFrame(tester);

      final state = container.read(serialPortManagerProvider);
      expect(state.connection.txBytes, 5);
      expect(serialManager.sentData, ['Hello']);
      expect(prefs.getStringList('send_input_history'), ['Hello']);
    });

    testWidgets('text is converted to hex when hex send is enabled',
        (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
        ),
      );
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), 'Hi');
      await pumpFrame(tester);

      container.read(uiSettingsProvider.notifier).setHexSend(true);
      await pumpFrame(tester);

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, '48 69');
    });

    testWidgets('valid hex is converted to text when hex send is disabled',
        (tester) async {
      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
          settings: const UiSettings(hexSend: true),
        ),
      );
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), '48 69');
      await pumpFrame(tester);

      container.read(uiSettingsProvider.notifier).setHexSend(false);
      await pumpFrame(tester);

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Hi');
    });

    testWidgets('history navigation restores temporary input', (tester) async {
      prefs.setStringList('send_input_history', ['One', 'Two']);

      await tester.pumpWidget(
        createSendInputTestWidget(
          prefs: prefs,
          container: container,
        ),
      );
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), 'Draft');
      await tester.tap(find.byType(TextFormField));
      await pumpFrame(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await pumpFrame(tester);
      var field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Two');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await pumpFrame(tester);
      field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'One');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await pumpFrame(tester);
      field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Two');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await pumpFrame(tester);
      field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Draft');
    });
  });
}
