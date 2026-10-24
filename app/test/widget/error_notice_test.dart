import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/host_core.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/widgets/shared/error_notice.dart';

void main() {
  testWidgets('error notices expire and can be closed manually', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showErrorNotice(context, StateError('failure')),
              child: const Icon(Icons.warning),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.warning));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byIcon(Icons.warning));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'partial writes keep byte progress and reveal raw diagnostics only on request',
    (tester) async {
      const rawMessage = 'native failure /dev/private-port';
      const error = rust.CoreError(
        kind: rust.ErrorKind.timeout,
        message: rawMessage,
        bytesWritten: 42,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showErrorNotice(context, error),
                child: const Icon(Icons.warning),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.warning));
      await tester.pumpAndSettle();
      final notice = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      expect(notice, contains('42'));
      expect(notice, matches(RegExp(r'[\u4e00-\u9fff]')));
      expect(notice, isNot(contains(rawMessage)));
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      final diagnostics = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      expect(diagnostics, contains(rawMessage));
      expect(diagnostics, contains('42'));
      expect(diagnostics, contains('timeout'));
    },
  );

  testWidgets(
    'startup summaries follow locale without exposing or losing the cause',
    (tester) async {
      final cause = StateError('private migration diagnostic');
      final locale = ValueNotifier(const Locale('zh'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StartupFailurePage(
              details: HostStartupException(
                HostFailure.preferenceMigration,
                cause,
              ),
            ),
          ),
        ),
      );
      final chinese = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(chinese, matches(RegExp(r'[\u4e00-\u9fff]')));
      expect(chinese, isNot(contains(cause.message)));
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      final english = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(english, isNot(chinese));
      expect(english, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
      expect(english, isNot(contains(cause.message)));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      final diagnostics = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      expect(diagnostics, contains(cause.message));
    },
  );
}
