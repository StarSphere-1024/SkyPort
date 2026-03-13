import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/providers/common_providers.dart';

// Mock class for SharedPreferences
class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier', () {
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = MockSharedPreferences();
    });

    test('build() loads system theme mode when no preference saved', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn(null);

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Assert
      final themeMode = container.read(themeModeProvider);
      expect(themeMode, ThemeMode.system);
    });

    test('build() loads light theme mode from preferences', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn('light');

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Assert
      final themeMode = container.read(themeModeProvider);
      expect(themeMode, ThemeMode.light);
    });

    test('build() loads dark theme mode from preferences', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn('dark');

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Assert
      final themeMode = container.read(themeModeProvider);
      expect(themeMode, ThemeMode.dark);
    });

    test('toggleTheme() switches from light to dark and saves', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn('light');
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) => Future.value(true));

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(themeModeProvider), ThemeMode.light);

      // Toggle
      container.read(themeModeProvider.notifier).toggleTheme();

      // Assert
      expect(container.read(themeModeProvider), ThemeMode.dark);
      verify(() => mockPrefs.setString('theme_mode', 'dark')).called(1);
    });

    test('toggleTheme() switches from dark to light and saves', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn('dark');
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) => Future.value(true));

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(themeModeProvider), ThemeMode.dark);

      // Toggle
      container.read(themeModeProvider.notifier).toggleTheme();

      // Assert
      expect(container.read(themeModeProvider), ThemeMode.light);
      verify(() => mockPrefs.setString('theme_mode', 'light')).called(1);
    });

    test('toggleTheme() switches from system to light and saves', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn(null);
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) => Future.value(true));

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(themeModeProvider), ThemeMode.system);

      // Toggle
      container.read(themeModeProvider.notifier).toggleTheme();

      // Assert
      expect(container.read(themeModeProvider), ThemeMode.light);
      verify(() => mockPrefs.setString('theme_mode', 'light')).called(1);
    });

    test('setThemeMode() sets specific mode and saves', () {
      // Arrange
      when(() => mockPrefs.getString(any())).thenReturn(null);
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) => Future.value(true));

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Set dark mode
      container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);

      // Assert
      expect(container.read(themeModeProvider), ThemeMode.dark);
      verify(() => mockPrefs.setString('theme_mode', 'dark')).called(1);
    });
  });

  group('ThemeColorNotifier', () {
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = MockSharedPreferences();
    });

    test('build() loads default color when no preference saved', () {
      // Arrange
      when(() => mockPrefs.getInt(any())).thenReturn(null);

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Assert
      final color = container.read(themeColorProvider);
      expect(color, Colors.blue);
    });

    test('build() loads custom color from preferences', () {
      // Arrange
      final customColor = Colors.green; // Use a simple color
      when(() => mockPrefs.getInt(any())).thenReturn(customColor.toARGB32());

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Assert - compare ARGB values instead of color objects
      final color = container.read(themeColorProvider);
      expect(color.toARGB32(), customColor.toARGB32());
    });

    test('setThemeColor() sets color and saves', () {
      // Arrange
      when(() => mockPrefs.getInt(any())).thenReturn(null);
      when(() => mockPrefs.setInt(any(), any())).thenAnswer((_) => Future.value(true));

      // Act
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      // Set custom color
      final customColor = Colors.green;
      container.read(themeColorProvider.notifier).setThemeColor(customColor);

      // Assert
      expect(container.read(themeColorProvider), customColor);
      verify(() => mockPrefs.setInt('theme_color', customColor.toARGB32()))
          .called(1);
    });
  });
}
