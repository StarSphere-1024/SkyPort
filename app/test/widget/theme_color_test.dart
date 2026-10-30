import 'dart:ui' show Tristate;

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
  Future<({SharedPreferences prefs, BuildContext context})> openSettings(
    WidgetTester tester, {
    Color initial = Colors.blue,
  }) async {
    SharedPreferences.setMockInitialValues({
      'theme_color': initial.toARGB32(),
      'ui_auto_check_updates': false,
    });
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
    await tester.tap(
      find.byTooltip(AppLocalizations.of(context).settingsPageLabel),
    );
    await tester.pumpAndSettle();
    return (prefs: prefs, context: context);
  }

  Future<void> openCustom(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-custom-color')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-custom-color')));
    await tester.pumpAndSettle();
  }

  final hexField = find.byKey(const ValueKey('theme-color-hex'));
  final apply = find.byKey(const ValueKey('theme-color-apply'));

  testWidgets(
    'dynamic color switch keeps manual editing enabled without status copy',
    (tester) async {
      final app = await openSettings(tester, initial: Colors.green);
      final switchFinder = find.byKey(const ValueKey('dynamic-color-switch'));
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(app.prefs.getBool('dynamic_color_enabled'), isTrue);

      await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
      await tester.pumpAndSettle();
      final red = find.byKey(ValueKey('theme-preset-${Colors.red.toARGB32()}'));
      await tester.ensureVisible(red);
      await tester.tap(red);
      await tester.pumpAndSettle();

      expect(app.prefs.getBool('dynamic_color_enabled'), isTrue);
      expect(app.prefs.getInt('theme_color'), Colors.red.toARGB32());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('narrow theme entry stays compact and opens palette', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(380, 753);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await openSettings(tester);
    final entry = find.byKey(const ValueKey('theme-color-scheme'));
    expect(tester.getSize(entry).height, lessThanOrEqualTo(72));
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final red = find.byKey(ValueKey('theme-preset-${Colors.red.toARGB32()}'));
    expect(red.hitTestable(), findsOneWidget);
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(app.prefs.getInt('theme_color'), Colors.red.toARGB32());
    expect(tester.getSize(entry).height, lessThanOrEqualTo(72));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset palette cards wrap horizontally', (tester) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    final blue = find.byKey(ValueKey('theme-preset-${Colors.blue.toARGB32()}'));
    final red = find.byKey(ValueKey('theme-preset-${Colors.red.toARGB32()}'));
    final blueTopLeft = tester.getTopLeft(blue);
    final redTopLeft = tester.getTopLeft(red);
    expect((blueTopLeft.dx - redTopLeft.dx).abs(), greaterThan(1));
    expect((blueTopLeft.dy - redTopLeft.dy).abs(), lessThan(1));
  });

  testWidgets('named preset updates theme and exclusive selection', (
    tester,
  ) async {
    final app = await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    final red = find.byKey(ValueKey('theme-preset-${Colors.red.toARGB32()}'));
    await tester.ensureVisible(red);
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(app.prefs.getInt('theme_color'), Colors.red.toARGB32());
    expect(
      Theme.of(app.context).colorScheme,
      ColorScheme.fromSeed(seedColor: Colors.red),
    );
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(red).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    final blue = find.byKey(ValueKey('theme-preset-${Colors.blue.toARGB32()}'));
    expect(
      tester.getSemantics(blue).flagsCollection.isSelected,
      Tristate.isFalse,
    );
  });

  testWidgets('Hex applies generated light and dark themes and reloads', (
    tester,
  ) async {
    final app = await openSettings(tester);
    await openCustom(tester);
    await tester.enterText(hexField, '  #aB34eF  ');
    await tester.pumpAndSettle();
    expect(app.prefs.getInt('theme_color'), Colors.blue.toARGB32());
    await tester.tap(apply);
    await tester.pumpAndSettle();
    const seed = Color(0xffab34ef);
    final container = ProviderScope.containerOf(app.context);
    expect(container.read(themeColorProvider), seed);
    expect(
      Theme.of(app.context).colorScheme,
      ColorScheme.fromSeed(seedColor: seed),
    );
    container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      Theme.of(app.context).colorScheme,
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
    );
    await app.prefs.reload();
    final reloaded = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(app.prefs)],
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.read(themeColorProvider), seed);
  });

  testWidgets('invalid Hex and alpha cannot submit', (tester) async {
    final app = await openSettings(tester);
    await openCustom(tester);
    for (final invalid in ['#123', '123456', '#12345678', '#GG1234', '']) {
      await tester.enterText(hexField, invalid);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      expect(
        tester.widget<TextField>(hexField).decoration!.errorText,
        isNotNull,
      );
      expect(app.prefs.getInt('theme_color'), Colors.blue.toARGB32());
    }
  });

  testWidgets('cancel, back and barrier discard custom edits', (tester) async {
    const old = Color(0xff123456);
    final app = await openSettings(tester, initial: old);
    final container = ProviderScope.containerOf(app.context);
    for (final dismissal in ['cancel', 'back', 'barrier']) {
      await openCustom(tester);
      expect(tester.widget<TextField>(hexField).controller!.text, '#123456');
      await tester.enterText(hexField, '#654321');
      await tester.pumpAndSettle();
      if (dismissal == 'cancel') {
        await tester.tap(find.byKey(const ValueKey('theme-color-cancel')));
      } else if (dismissal == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(container.read(themeColorProvider), old);
      expect(app.prefs.getInt('theme_color'), old.toARGB32());
    }
  });

  testWidgets('visual channels and Hex share the same pending seed', (
    tester,
  ) async {
    final app = await openSettings(tester);
    await openCustom(tester);
    await tester.enterText(hexField, '#123456');
    await tester.pumpAndSettle();
    final red = find.byKey(const ValueKey('theme-color-red'));
    final green = find.byKey(const ValueKey('theme-color-green'));
    final blue = find.byKey(const ValueKey('theme-color-blue'));
    expect(tester.widget<Slider>(red).value, 0x12);
    expect(tester.widget<Slider>(green).value, 0x34);
    expect(tester.widget<Slider>(blue).value, 0x56);
    await tester.tapAt(tester.getCenter(red));
    await tester.pumpAndSettle();
    final selected = tester.widget<Slider>(red).value.round();
    final expected = Color.fromARGB(255, selected, 0x34, 0x56);
    expect(
      tester.widget<TextField>(hexField).controller!.text,
      '#${expected.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
    );
    expect(app.prefs.getInt('theme_color'), Colors.blue.toARGB32());
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(app.context).read(themeColorProvider),
      expected,
    );
    expect(app.prefs.getInt('theme_color'), expected.toARGB32());
  });

  testWidgets('old non-preset seed stays selected as custom', (tester) async {
    const old = Color(0xff9c27b0);
    final app = await openSettings(tester, initial: old);
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    expect(find.text('#9C27B0'), findsWidgets);
    final custom = find.byKey(const ValueKey('theme-custom-color'));
    expect(
      tester.getSemantics(custom).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      ProviderScope.containerOf(app.context).read(themeColorProvider),
      old,
    );
    expect(app.prefs.getInt('theme_color'), old.toARGB32());
  });

  testWidgets('unsubmitted log capacity survives theme and panel changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ui_auto_check_updates': false});
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-color-scheme')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-color-scheme')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('theme-preset-${Colors.red.toARGB32()}')),
    );
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
    SharedPreferences.setMockInitialValues({'ui_auto_check_updates': false});
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
