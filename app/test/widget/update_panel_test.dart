import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/services/update_service.dart';
import 'package:skyport/widgets/update_panel.dart';

class _AvailableUpdate extends UpdateService {
  @override
  Future<AppRelease?> check(String currentVersion) async => AppRelease(
    version: '2.0.8',
    notes: 'Release details',
    pageUrl: Uri.https('github.com', '/StarSphere-1024/SkyPort/releases'),
    assets: const [],
  );
}

void main() {
  testWidgets(
    'checking ends before opening details and closing restores only the button',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'SkyPort',
        packageName: 'skyport',
        version: '2.0.7',
        buildNumber: '0',
        buildSignature: '',
      );
      final service = _AvailableUpdate();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: UpdatePanel(updateService: service)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UpdatePanel)),
      );
      await tester.tap(find.text(l10n.checkForUpdates));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Release details'), findsOneWidget);
      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Release details'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
}
