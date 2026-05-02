import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
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

    testWidgets('renders send setting controls', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.textContaining('Hex'), findsOneWidget);
      expect(find.textContaining('Auto'), findsOneWidget);
      expect(find.textContaining('Newline'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('accepts interval input', (tester) async {
      await tester.pumpWidget(createTestWidget());

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '5');
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });
  });
}
