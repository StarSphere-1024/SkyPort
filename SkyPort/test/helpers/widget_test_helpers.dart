import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import '../helpers/mock_classes.dart';

/// Creates a test widget with all necessary providers and localization
Widget createTestWidget({
  required Widget child,
  List overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(FakeSharedPreferences()),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: Material(child: child),
    ),
  );
}

/// Creates a testable widget wrapped in Material and ProviderScope
Widget testableWidget(
  Widget child, {
  List overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(FakeSharedPreferences()),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: Scaffold(body: child),
    ),
  );
}

/// Finds text by localization key
Finder findTextByKey(String key) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data?.contains(key) == true,
  );
}

// ========== Additional Widget Test Helpers ==========

/// Finds a DropdownMenu with a specific initial value
Finder findDropdownWithValue(dynamic value) {
  return find.byWidgetPredicate((widget) =>
      widget is DropdownMenu<dynamic> && widget.initialSelection == value);
}

/// Finds a FilledButton with specific text
Finder findButtonWithText(String text) {
  return find.byWidgetPredicate((widget) =>
      widget is FilledButton &&
      widget.child is Text &&
      (widget.child as Text).data == text);
}

/// Finds a TextButton with specific text
Finder findTextButtonWithText(String text) {
  return find.byWidgetPredicate((widget) =>
      widget is TextButton &&
      widget.child is Text &&
      (widget.child as Text).data == text);
}

/// Finds a Switch with specific value
Finder findSwitchWithValue(bool value) {
  return find.byWidgetPredicate((widget) =>
      widget is Switch && widget.value == value);
}

/// Finds a TextField with specific hint text
Finder findTextFieldWithHint(String hint) {
  return find.byWidgetPredicate((widget) =>
      widget is TextField &&
      widget.decoration?.hintText == hint);
}


/// Pumps a widget and settles all animations
Future<void> pumpAndSettle(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

/// Enters text in a TextFormField and pumps
Future<void> enterFormField(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

/// Taps a widget and pumps
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Verifies a widget exists and is visible
void expectVisible(Finder finder, WidgetTester tester) {
  expect(finder, findsOneWidget);
  final widget = tester.widget(finder);
  expect(widget, isNotNull);
}
