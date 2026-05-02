import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/widgets/status_bar.dart';

import '../helpers/mock_classes.dart';

void main() {
  group('StatusBar Widget', () {
    late FakeSharedPreferences prefs;
    late MockSerialPortService mockService;

    setUpAll(registerFallbackValues);

    setUp(() {
      prefs = FakeSharedPreferences()..setString('serial_port_name', 'COM1');
      mockService = MockSerialPortService();
      setupMockSerialPortService(mockService);
    });

    Widget createWidget() {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serialPortServiceProvider.overrideWithValue(mockService),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en', 'US'),
          home: Scaffold(body: StatusBar()),
        ),
      );
    }

    testWidgets('renders status bar and stats', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(StatusBar), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });
}
