import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/services/update_service.dart';
import 'package:skyport/widgets/update_panel.dart';

final _page = Uri.https(
  'github.com',
  '/StarSphere-1024/SkyPort/releases/tag/v2.0.8',
);

class _AvailableUpdate extends UpdateService {
  @override
  Future<AppRelease?> check(String currentVersion) async =>
      AppRelease(version: '2.0.8', pageUrl: _page);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'SkyPort',
      packageName: 'skyport',
      version: '2.0.7',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final service = _AvailableUpdate();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: UpdatePanel(updateService: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(UpdatePanel)));
    await tester.tap(find.text(l10n.checkForUpdates));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('ignore persists and manual checking can undo it', (
    tester,
  ) async {
    final container = await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reopened.dispose);
    expect(reopened.read(uiSettingsProvider).ignoredUpdateVersion, '2.0.8');
    await tester.tap(find.text(l10n.updateLater));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text(l10n.checkForUpdates));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(container.read(uiSettingsProvider).ignoredUpdateVersion, '');
    expect(prefs.getString('ui_ignored_update_version'), '');
  });

  for (final succeeds in [true, false]) {
    testWidgets('external release launch succeeds=$succeeds', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return succeeds;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await open(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      await tester.tap(find.text(l10n.updateReleasePage));
      await tester.pumpAndSettle();
      final launch = calls.singleWhere((call) => call.method == 'launch');
      expect(launch.arguments['url'], _page.toString());
      expect(launch.arguments['useWebView'], isFalse);
      expect(launch.arguments['useSafariVC'], isFalse);
      expect(
        find.byType(AlertDialog),
        succeeds ? findsNothing : findsOneWidget,
      );
      if (!succeeds) {
        expect(find.text(l10n.updateErrorOpenPage), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.updateReleasePage),
              )
              .onPressed,
          isNotNull,
        );
      }
    });
  }
}
