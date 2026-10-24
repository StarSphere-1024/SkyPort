import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/providers/ui_controller.dart';

import 'home_page_test.dart' show LayoutController;

void main() {
  testWidgets('theme color selection is exclusive and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(LayoutController.new),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const SerialDebuggerApp(),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomePage));
    final l10n = AppLocalizations.of(context);
    await tester.tap(find.byTooltip(l10n.settingsPageLabel));
    await tester.pumpAndSettle();
    final red = find.byTooltip('${l10n.themeColor} #F44336');
    await tester.ensureVisible(red);
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(context).read(themeColorProvider),
      Colors.red,
    );
    expect(prefs.getInt('theme_color'), Colors.red.toARGB32());
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.isSelected == true,
      ),
      findsOneWidget,
    );
    final blue = find.byTooltip('${l10n.themeColor} #2196F3');
    await tester.tap(blue);
    await tester.pumpAndSettle();
    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );
    expect(button('${l10n.themeColor} #F44336').isSelected, isFalse);
    expect(button('${l10n.themeColor} #2196F3').isSelected, isTrue);
    expect(prefs.getInt('theme_color'), Colors.blue.toARGB32());
    expect(tester.takeException(), isNull);
  });
}
