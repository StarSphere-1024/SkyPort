import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';

import 'home_page_test.dart' show LayoutController;

class _Preferences extends Mock implements SharedPreferences {}

void main() {
  testWidgets('language override persists and can return to system selection', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues({'ui_auto_check_updates': false});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer? container;
    addTearDown(() => container?.dispose());

    Future<void> mount() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      await prefs.reload();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          uiControllerProvider.overrideWith(LayoutController.new),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container!,
          child: const SerialDebuggerApp(),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
      await tester.tap(find.byTooltip(l10n.settingsPageLabel));
      await tester.pumpAndSettle();
    }

    String currentLanguage() => Localizations.localeOf(
      tester.element(find.byType(HomePage)),
    ).languageCode;

    Future<void> choose(String label) async {
      final dropdown = find.byKey(const ValueKey('language-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await mount();
    await choose('简体中文');
    expect(currentLanguage(), 'zh');
    expect(prefs.getString('ui_language_code'), 'zh');

    await mount();
    expect(currentLanguage(), 'zh');
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    await tester.pumpAndSettle();
    expect(currentLanguage(), 'zh');

    await choose(
      AppLocalizations.of(tester.element(find.byType(HomePage))).followSystem,
    );
    expect(currentLanguage(), 'en');
    tester.platformDispatcher.localesTestValue = [const Locale('zh', 'TW')];
    await tester.pumpAndSettle();
    expect(currentLanguage(), 'zh');
    await mount();
    expect(currentLanguage(), 'zh');
    expect(container!.read(uiSettingsProvider).languageCode, '');

    await choose('English');
    expect(currentLanguage(), 'en');
    container!.read(uiSettingsProvider.notifier).setShowTimestamp(false);
    await tester.pumpAndSettle();
    expect(currentLanguage(), 'en');
    await mount();
    expect(currentLanguage(), 'en');
  });

  test('a failed save leaves the active language unchanged', () async {
    final prefs = _Preferences();
    when(() => prefs.getBool(any())).thenReturn(null);
    when(() => prefs.getString(any())).thenReturn(null);
    when(() => prefs.getString('ui_language_code')).thenReturn('en');
    when(
      () => prefs.setString('ui_language_code', 'zh'),
    ).thenAnswer((_) async => false);
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(uiSettingsProvider.notifier).setLanguageCode('zh'),
      throwsStateError,
    );
    expect(container.read(uiSettingsProvider).languageCode, 'en');
  });
}
