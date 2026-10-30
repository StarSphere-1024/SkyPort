import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/widgets/about_panel.dart';

void main() {
  testWidgets('failed browser launch leaves a copyable project link', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'SkyPort',
      packageName: 'skyport',
      version: '2.0.5',
      buildNumber: '0',
      buildSignature: '',
    );
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => false,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AboutPanel()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.open_in_new_rounded));
    await tester.tap(find.byIcon(Icons.open_in_new_rounded));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(AboutPanel)));
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.projectLinkOpenFailed),
      ),
      findsOneWidget,
    );
    expect(
      find
          .widgetWithText(SelectableText, 'github.com/StarSphere-1024/SkyPort')
          .hitTestable(),
      findsOneWidget,
    );
  });
}
