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
