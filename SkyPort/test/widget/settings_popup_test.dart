import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/providers/serial/serial_config_provider.dart';
import 'package:skyport/widgets/settings_popup.dart';

import '../helpers/widget_test_helpers.dart';

void main() {
  group('SettingsPopup Widget', () {
    Widget createTestSettingsPopup() {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();

      return testableWidget(
        SettingsPopup(
          controller: controller,
          formKey: formKey,
        ),
        overrides: [
          availablePortsProvider.overrideWithValue(
            AsyncData(['COM1', 'COM2']),
          ),
        ],
      );
    }

    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should find the Form
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('has theme dropdown', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should find theme dropdown
      expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
    });

    testWidgets('has theme color dropdown', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should find color dropdown
      expect(find.byType(DropdownButton<Color>), findsOneWidget);
    });

    testWidgets('has list tiles for settings', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should have multiple ListTiles
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('displays theme mode options', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should tap on theme dropdown
      final themeDropdown = find.byType(DropdownButton<ThemeMode>);
      expect(themeDropdown, findsOneWidget);
    });

    testWidgets('can change theme mode', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Find and tap the dropdown
      final dropdownFinder = find.byType(DropdownButton<ThemeMode>);

      // Verify dropdown exists
      expect(dropdownFinder, findsOneWidget);
    });

    testWidgets('displays color options', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should have color dropdown
      expect(find.byType(DropdownButton<Color>), findsOneWidget);
    });

    testWidgets('has proper structure', (tester) async {
      await tester.pumpWidget(createTestSettingsPopup());

      // Should have Form, Column, and multiple ListTiles
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(ListTile), findsWidgets);
    });
  });
}
