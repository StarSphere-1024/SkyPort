import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/common_providers.dart';
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

    testWidgets('renders all labels and switches', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('Hex Display'), findsOneWidget);
      expect(find.text('Show Timestamp'), findsOneWidget);
      expect(find.text('Show Sent Data'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(3));
    });

    testWidgets('renders provided ui settings', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          settings: const UiSettings(
            hexDisplay: true,
            showTimestamp: false,
            showSent: true,
          ),
        ),
      );

      expect(find.byType(ReceiveSettingsWidget), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(3));
    });
  });
}
