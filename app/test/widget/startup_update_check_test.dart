import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/services/update_service.dart';
import 'package:skyport/widgets/startup_update_check.dart';

class _PendingCheck extends UpdateService {
  final result = Completer<AppRelease?>();

  @override
  Future<AppRelease?> check(String currentVersion) => result.future;
}

void main() {
  testWidgets(
    'disabling automatic checks suppresses an in-flight result and persists',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ui_auto_check_updates': true});
      PackageInfo.setMockInitialValues(
        appName: 'SkyPort',
        packageName: 'skyport',
        version: '2.0.6',
        buildNumber: '0',
        buildSignature: '',
      );
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final service = _PendingCheck();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StartupUpdateCheck(
              updateService: service,
              child: const Scaffold(
                body: Text('Serial debugging remains available'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await container
          .read(uiSettingsProvider.notifier)
          .setAutoCheckUpdates(false);
      service.result.complete(
        AppRelease(
          version: '2.0.7',
          notes: 'New release',
          pageUrl: Uri.https(
            'github.com',
            '/StarSphere-1024/SkyPort/releases/tag/v2.0.7',
          ),
          assets: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Serial debugging remains available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);
      expect(reopened.read(uiSettingsProvider).autoCheckUpdates, isFalse);
    },
  );
}
