import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/theme_provider.dart';

void main() {
  group('theme color source resolution', () {
    test('system accent wins without changing the saved manual seed', () async {
      SharedPreferences.setMockInitialValues({
        'theme_color': 0xff123456,
        'dynamic_color_enabled': true,
        'dynamic_color_preference_initialized': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      container.read(systemAccentColorProvider.notifier).setColor(Colors.red);
      final result = resolveThemeColor(
        dynamicEnabled: container.read(dynamicColorEnabledProvider),
        manualSeed: container.read(themeColorProvider),
        systemAccent: container.read(systemAccentColorProvider),
        brightness: Brightness.light,
      );

      expect(result.source, ThemeColorSource.system);
      expect(result.seed, Colors.red);
      expect(prefs.getInt('theme_color'), 0xff123456);
    });

    test('missing system accent reports manual or default fallback', () async {
      SharedPreferences.setMockInitialValues({'theme_color': 0xff123456});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final saved = resolveThemeColor(
        dynamicEnabled: true,
        manualSeed: container.read(themeColorProvider),
        systemAccent: null,
        brightness: Brightness.light,
      );
      expect(saved.source, ThemeColorSource.manual);
      expect(saved.seed, const Color(0xff123456));

      SharedPreferences.setMockInitialValues({});
      final emptyPrefs = await SharedPreferences.getInstance();
      final empty = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(emptyPrefs)],
      );
      addTearDown(empty.dispose);
      final fallback = resolveThemeColor(
        dynamicEnabled: true,
        manualSeed: null,
        systemAccent: null,
        brightness: Brightness.dark,
      );
      expect(fallback.source, ThemeColorSource.defaultColor);
      expect(fallback.seed, Colors.blue);
    });

    test(
      'disabling dynamic restores manual seed and brightness stays independent',
      () async {
        SharedPreferences.setMockInitialValues({
          'theme_color': 0xff123456,
          'theme_mode': 'dark',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await container
            .read(dynamicColorEnabledProvider.notifier)
            .setEnabled(false);
        final manual = resolveThemeColor(
          dynamicEnabled: container.read(dynamicColorEnabledProvider),
          manualSeed: container.read(themeColorProvider),
          systemAccent: Colors.red,
          brightness: Brightness.dark,
        );

        expect(manual.source, ThemeColorSource.manual);
        expect(manual.seed, const Color(0xff123456));
        expect(container.read(themeModeProvider), ThemeMode.dark);
        expect(prefs.getString('theme_mode'), 'dark');
      },
    );

    test('platform accent updates affect only dynamic resolution', () async {
      SharedPreferences.setMockInitialValues({'theme_color': 0xff123456});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final manualSeed = container.read(themeColorProvider);

      container.read(systemAccentColorProvider.notifier).setColor(Colors.red);
      final dynamic = resolveThemeColor(
        dynamicEnabled: true,
        manualSeed: manualSeed,
        systemAccent: container.read(systemAccentColorProvider),
        brightness: Brightness.light,
      );
      final manual = resolveThemeColor(
        dynamicEnabled: false,
        manualSeed: manualSeed,
        systemAccent: container.read(systemAccentColorProvider),
        brightness: Brightness.light,
      );

      expect(dynamic.seed, Colors.red);
      expect(manual.seed, const Color(0xff123456));
      expect(prefs.getInt('theme_color'), 0xff123456);
    });

    test('editing fallback seed preserves enabled dynamic mode', () async {
      SharedPreferences.setMockInitialValues({
        'theme_color': 0xff123456,
        'theme_mode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await container
          .read(dynamicColorEnabledProvider.notifier)
          .setEnabled(true);

      container.read(themeColorProvider.notifier).setThemeColor(Colors.green);

      final result = resolveThemeColor(
        dynamicEnabled: container.read(dynamicColorEnabledProvider),
        manualSeed: container.read(themeColorProvider),
        systemAccent: null,
        brightness: Brightness.dark,
      );
      expect(result.source, ThemeColorSource.manual);
      expect(result.seed, Colors.green);
      expect(container.read(dynamicColorEnabledProvider), isTrue);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('dynamic color preference migration', () {
    test('new installs enable dynamic colors by default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(dynamicColorEnabledProvider), isTrue);
      expect(prefs.getBool('dynamic_color_enabled'), isTrue);
    });

    test(
      'an existing install with only frontend prefs defaults to manual',
      () async {
        SharedPreferences.setMockInitialValues({'ui_hex_send': true});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(dynamicColorEnabledProvider), isFalse);
        expect(prefs.getBool('dynamic_color_enabled'), isFalse);
      },
    );
    test(
      'legacy theme preferences remain manual and migration is stable',
      () async {
        SharedPreferences.setMockInitialValues({
          'theme_mode': 'dark',
          'theme_color': 0xff123456,
        });
        final prefs = await SharedPreferences.getInstance();
        final first = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );

        expect(first.read(dynamicColorEnabledProvider), isFalse);
        expect(first.read(themeModeProvider), ThemeMode.dark);
        expect(first.read(themeColorProvider), const Color(0xff123456));
        expect(prefs.getBool('dynamic_color_enabled'), isFalse);
        first.dispose();

        await prefs.reload();
        final restarted = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(restarted.dispose);
        expect(restarted.read(dynamicColorEnabledProvider), isFalse);
        expect(restarted.read(themeModeProvider), ThemeMode.dark);
        expect(restarted.read(themeColorProvider), const Color(0xff123456));
      },
    );
  });
}
