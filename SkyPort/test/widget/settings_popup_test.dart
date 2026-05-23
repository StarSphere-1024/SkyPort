import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/connection_status.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/models/serial_port_state.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/widgets/settings_popup.dart';

import '../helpers/mock_classes.dart';

Future<void> pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class TestSerialPortManager extends SerialPortManager {
  @override
  SerialPortState build() {
    return SerialPortState(
      targetConfig: SerialConfig(portName: 'COM1', autoReconnect: true),
      connection: const ConnectionStatus(),
      availablePorts: const ['COM1'],
    );
  }

  @override
  void setAutoReconnect(bool value) {
    state = state.copyWith(
      targetConfig: state.targetConfig.copyWith(autoReconnect: value),
    );
    ref.read(sharedPreferencesProvider).setBool('serial_auto_reconnect', value);
  }
}

void main() {
  group('SettingsPopup Widget', () {
    late FakeSharedPreferences prefs;
    late ProviderContainer container;
    late TextEditingController controller;
    late GlobalKey<FormState> formKey;
    late TestSerialPortManager serialManager;

    setUpAll(registerFallbackValues);

    setUp(() {
      prefs = FakeSharedPreferences()
        ..setString('serial_port_name', 'COM1')
        ..setBool('serial_auto_reconnect', true);
      serialManager = TestSerialPortManager();
      controller = TextEditingController(text: '128');
      formKey = GlobalKey<FormState>();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serialPortManagerProvider.overrideWith(() => serialManager),
        ],
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    Widget createTestSettingsPopup() {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: Scaffold(
            body: SettingsPopup(
              controller: controller,
              formKey: formKey,
            ),
          ),
        ),
      );
    }

    testWidgets('renders base structure', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());
      await pumpFrame(tester);

      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(ListTile), findsWidgets);
      expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
      expect(find.byType(DropdownButton<Color>), findsOneWidget);
    });

    testWidgets('theme dropdown updates saved theme mode', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());
      await pumpFrame(tester);

      await tester.tap(find.byType(DropdownButton<ThemeMode>));
      await pumpFrame(tester);
      await tester.tap(find.text('Dark').last);
      await pumpFrame(tester);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(prefs.getString('theme_mode'), 'dark');
    });

    testWidgets('switches update UI and serial settings', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());
      await pumpFrame(tester);

      await tester.tap(find.byType(Switch).first);
      await pumpFrame(tester);

      expect(container.read(uiSettingsProvider).enableAnsi, true);
      expect(prefs.getBool('ui_enable_ansi'), true);

      await tester.tap(find.byType(Switch).at(1));
      await pumpFrame(tester);

      expect(
        container.read(serialPortManagerProvider).targetConfig.autoReconnect,
        false,
      );
      expect(prefs.getBool('serial_auto_reconnect'), false);
    });

    testWidgets('log buffer field validates and saves values', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());
      await pumpFrame(tester);

      await tester.enterText(find.byType(TextFormField), '8');
      await pumpFrame(tester);

      expect(formKey.currentState?.validate(), false);
      await pumpFrame(tester);
      expect(find.text('16-512'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '256');
      await pumpFrame(tester);

      expect(formKey.currentState?.validate(), true);
      formKey.currentState?.save();

      expect(container.read(uiSettingsProvider).logBufferSize, 256);
      expect(prefs.getInt('ui_log_buffer_size'), 256);
    });
  });
}
