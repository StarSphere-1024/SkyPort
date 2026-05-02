import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/widgets/settings_popup.dart';

import '../helpers/mock_classes.dart';

void main() {
  group('SettingsPopup Widget', () {
    late FakeSharedPreferences prefs;
    late MockSerialPortService mockService;

    setUpAll(registerFallbackValues);

    setUp(() {
      prefs = FakeSharedPreferences()
        ..setString('serial_port_name', 'COM1')
        ..setBool('serial_auto_reconnect', true);
      mockService = MockSerialPortService();
      setupMockSerialPortService(mockService);
    });

    Widget createTestSettingsPopup() {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();

      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serialPortServiceProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
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
      await tester.pumpAndSettle();

      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(ListTile), findsWidgets);
      expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
      expect(find.byType(DropdownButton<Color>), findsOneWidget);
    });
  });
}
