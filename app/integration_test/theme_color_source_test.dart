import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/providers/ui_controller.dart';

import '../test/widget/home_page_test.dart' show LayoutController;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux platform accent uses system color or manual fallback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ui_auto_check_updates': false,
      'dynamic_color_enabled': true,
      'dynamic_color_preference_initialized': true,
      'theme_color': 0xff123456,
      'theme_mode': 'light',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        uiControllerProvider.overrideWith(LayoutController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SerialDebuggerApp(),
      ),
    );
    await tester.pumpAndSettle();

    Color? systemAccent;
    try {
      systemAccent = await DynamicColorPlugin.getAccentColor();
    } on PlatformException {
      systemAccent = null;
    } on MissingPluginException {
      systemAccent = null;
    }
    container.read(systemAccentColorProvider.notifier).setColor(systemAccent);
    await tester.pumpAndSettle();

    final home = tester.element(find.byType(HomePage));
    final l10n = AppLocalizations.of(home);
    await tester.tap(find.byTooltip(l10n.settingsPageLabel));
    await tester.pumpAndSettle();

    if (systemAccent == null) {
      expect(find.byKey(const ValueKey('theme-color-scheme')), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(HomePage))).colorScheme.primary,
        ColorScheme.fromSeed(seedColor: const Color(0xff123456)).primary,
      );
    } else {
      expect(find.byKey(const ValueKey('theme-color-scheme')), findsNothing);
      expect(
        Theme.of(tester.element(find.byType(HomePage))).colorScheme.primary,
        ColorScheme.fromSeed(seedColor: systemAccent).primary,
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
