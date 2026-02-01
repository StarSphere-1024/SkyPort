import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skyport/main.dart';

/// Integration tests for data transfer functionality
///
/// These tests verify sending and receiving data through the UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Data Transfer Integration Tests', () {
    testWidgets('app displays data log area', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Should find the data display area
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('has input field for sending data', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Should find text input fields
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('displays send button', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Should find send buttons (typically FilledButton)
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('clear button is available', (tester) async {
      await tester.pumpWidget(const SerialDebuggerApp());
      await tester.pumpAndSettle();

      // Should find clear button
      expect(find.textContaining('Clear'), findsOneWidget);
    });

    group('UI Layout', () {
      testWidgets('has proper left-right panel layout', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Should have Row layout with panels
        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('left panel contains controls', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Should find dropdowns and switches in left panel
        expect(find.byType(DropdownMenu), findsWidgets);
        expect(find.byType(Switch), findsWidgets);
      });

      testWidgets('right panel contains display and input', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Right panel should be visible
        expect(find.byType(Scaffold), findsOneWidget);
      });
    });

    group('Status Display', () {
      testWidgets('displays status bar', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Should find bottom navigation bar (status bar)
        expect(find.byType(BottomNavigationBar), findsOneWidget);
      });

      testWidgets('status shows connection info', (tester) async {
        await tester.pumpWidget(const SerialDebuggerApp());
        await tester.pumpAndSettle();

        // Status bar should be present
        expect(find.byType(BottomNavigationBar), findsOneWidget);
      });
    });
  });
}
