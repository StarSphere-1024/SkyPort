import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/widgets/application_settings.dart';

import 'home_page_test.dart' show LayoutController;

class SettingsController extends LayoutController {
  int? submittedCapacity;

  @override
  Future<void> setLogCapacity(int megabytes) async {
    submittedCapacity = megabytes;
  }
}

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

  testWidgets('unsubmitted log capacity survives theme and panel changes', (
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
    final container = ProviderScope.containerOf(context);
    final settings = find.byTooltip(l10n.settingsPageLabel);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    final buffer = find.descendant(
      of: find.byType(ApplicationSettings),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(buffer);
    await tester.enterText(buffer, '256');
    await tester.ensureVisible(find.byType(DropdownButton<ThemeMode>));
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dark).last);
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await tester.tap(find.byTooltip('${l10n.themeColor} #F44336'));
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(buffer).controller!.text, '256');
    expect(
      container.read(uiControllerProvider).logCapacityBytes,
      128 * 1024 * 1024,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('short narrow settings scroll to editable bottom controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'getDirectoryPath' ? '/tmp/skyport-logs' : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(SettingsController.new),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const SerialDebuggerApp(),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomePage));
    final l10n = AppLocalizations.of(context);
    final controller =
        ProviderScope.containerOf(context).read(uiControllerProvider.notifier)
            as SettingsController;
    await tester.tap(find.byTooltip(l10n.settingsPageLabel));
    await tester.pumpAndSettle();
    final buffer = find.descendant(
      of: find.byType(ApplicationSettings),
      matching: find.byType(TextFormField),
    );
    expect(buffer.hitTestable(), findsNothing);
    await tester.drag(
      find.descendant(
        of: find.byType(ApplicationSettings),
        matching: find.byType(DropdownButton<ThemeMode>),
      ),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(buffer);
    expect(buffer.hitTestable(), findsOneWidget);
    await tester.enterText(buffer, '15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.submittedCapacity, isNull);
    expect(find.text(l10n.logBufferSizeError), findsOneWidget);
    await tester.enterText(buffer, '64');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.submittedCapacity, 64);
    final directory = find.text(l10n.exportPathHint).last;
    await tester.ensureVisible(directory);
    expect(directory.hitTestable(), findsOneWidget);
    await tester.tap(directory);
    await tester.pumpAndSettle();
    expect(find.text('/tmp/skyport-logs'), findsOneWidget);
    expect(prefs.getString('ui_log_export_path'), '/tmp/skyport-logs');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
