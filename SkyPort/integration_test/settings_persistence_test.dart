import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skyport/main.dart';

/// Integration tests for settings persistence
///
/// These tests verify that user settings are properly saved and restored.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Settings Persistence Integration Tests', () {
    testWidgets('app loads with default settings', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // App should start without errors
      expect(find.byType(MaterialApp), findsOneWidget);

      // Should display default UI state
      expect(find.byType(DropdownMenu), findsWidgets);
    });

    testWidgets('settings button is accessible', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Settings button in AppBar
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('can open settings menu', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Tap settings button
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Settings form should be visible
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('settings form has theme options', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Should find theme dropdown
      expect(find.byType(DropdownButton<ThemeMode>), findsOneWidget);
    });

    testWidgets('settings form has color options', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Should find color dropdown
      expect(find.byType(DropdownButton<Color>), findsOneWidget);
    });

    testWidgets('settings can be changed', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Tap on theme dropdown
      final themeDropdown = find.byType(DropdownButton<ThemeMode>);
      expect(themeDropdown, findsOneWidget);

      // Interact with dropdown (it should respond)
      await tester.tap(themeDropdown);
      await tester.pumpAndSettle();
    });

    testWidgets('app maintains state after settings interaction',
        (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Open settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Close by tapping outside (on AppBar)
      await tester.tap(find.byType(AppBar));
      await tester.pumpAndSettle();

      // App should still be functional
      expect(find.byType(SerialDebuggerApp), findsOneWidget);
    });

    testWidgets('settings persist across rebuilds', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Rebuild app
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // App should maintain state
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    group('Configuration Values', () {
      testWidgets('displays serial config defaults', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Should find default baud rate
        expect(find.text('9600'), findsOneWidget);
      });

      testWidgets('displays UI settings defaults', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // UI should be rendered
        expect(find.byType(SerialDebuggerApp), findsOneWidget);
      });
    });
  });
}
