import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/search_controller.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/widgets/right_panel/receive_display_widget.dart';

import '../../helpers/search_fixture.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    SearchFixtureController logs,
    FixtureSearchBackend backend,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(() => logs),
          uiSettingsProvider.overrideWith(SearchFixtureSettings.new),
          searchBackendProvider.overrideWithValue(backend),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                ReceiveDisplayWidget(),
                TextField(key: ValueKey('send-draft')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ReceiveDisplayWidget)),
  );

  testWidgets(
    'typing never searches; Enter always submits; Esc preserves draft',
    (tester) async {
      final logs = SearchFixtureController();
      final backend = FixtureSearchBackend(logs, [
        FixtureSearchSession(),
        FixtureSearchSession(),
      ]);
      await mount(tester, logs, backend);
      await tester.tap(find.byKey(const ValueKey('send-draft')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('search-input'));
      expect(input, findsOneWidget);
      await tester.enterText(input, '  literal  ');
      await tester.pump(const Duration(milliseconds: 500));
      expect(backend.submissions, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(backend.submissions.single.$1, '  literal  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(backend.submissions, hasLength(2));
      await tester.enterText(input, 'new draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'new draft');
      expect(backend.submissions, hasLength(2));
      final toggle = find.byKey(const ValueKey('search-open'));
      expect(
        find.descendant(of: toggle, matching: find.text('Search')),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'new draft');
      expect(backend.submissions, hasLength(2));
    },
  );

  testWidgets(
    'narrow attached bar has usable submit and options apply only on submit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final logs = SearchFixtureController();
      final backend = FixtureSearchBackend(logs, [
        FixtureSearchSession(),
        FixtureSearchSession(),
      ]);
      await mount(tester, logs, backend);
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('search-input')), '41');
      final fieldBounds = tester.getRect(
        find.byKey(const ValueKey('search-input')),
      );
      for (final key in [
        'search-submit',
        'search-previous',
        'search-next',
        'search-close',
      ]) {
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.center.dy, closeTo(fieldBounds.center.dy, 1));
        expect(bounds.right, lessThanOrEqualTo(360));
      }
      await tester.tap(find.byKey(const ValueKey('search-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-case')));
      final settings = container(tester).read(uiSettingsProvider.notifier);
      settings.setHexDisplay(true);
      settings.setShowSent(false);
      settings.setEnableAnsi(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-case')), findsNothing);
      expect(backend.submissions, hasLength(1));
      expect(
        container(tester).read(searchControllerProvider).options!.hex,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('search-submit')));
      await tester.pumpAndSettle();
      final options = backend.submissions.last.$2;
      expect(options.hex, isTrue);
      expect(options.showSent, isFalse);
      expect(options.stripAnsi, isTrue);
      expect(options.caseSensitive, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F3/ShiftF3 wrap and jump to exact variable-height retained record',
    (tester) async {
      final logs = SearchFixtureController();
      const source = 'prefix needle suffix';
      const range = rust.SearchRange(start: 7, end: 13);
      final session = FixtureSearchSession(
        hits: [fixtureHit(1, 0, source.length), fixtureHit(900, 1, 20000)],
        views: {
          1: fixtureView(1, source, ranges: [range], focus: range),
          900: fixtureView(
            900,
            source,
            sourceLength: 20000,
            ranges: [range],
            focus: range,
            leadingClipped: true,
            trailingClipped: true,
          ),
        },
      );
      await mount(tester, logs, FixtureSearchBackend(logs, [session]));
      logs.upsert([
        for (var id = 1; id <= 1000; id++)
          fixtureRecord(
            id,
            id == 1
                ? source
                : id == 900
                ? 'x' * 20000
                : 'row $id ${'variable height data ' * (id % 17)}',
          ),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        'needle',
      );
      await tester.tap(find.byKey(const ValueKey('search-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-row-1')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-row-900')), findsOneWidget);
      expect(find.text('… earlier context clipped'), findsOneWidget);
      expect(find.text('later context clipped …'), findsOneWidget);
      final body = find.descendant(
        of: find.byKey(const ValueKey('search-row-900')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('prefix needle suffix'),
        ),
      );
      expect(tester.getRect(body).top, greaterThanOrEqualTo(0));
      expect(
        tester.getRect(body).top,
        lessThan(tester.view.physicalSize.height),
      );
      expect(session.requestedViews, contains((900, 1)));
      final rendered = tester.widget<RichText>(body).text.toPlainText();
      expect(rendered, contains('RX < prefix needle suffix'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(container(tester).read(searchControllerProvider).selectedIndex, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(container(tester).read(searchControllerProvider).selectedIndex, 1);
      expect(find.byKey(const ValueKey('search-row-900')), findsOneWidget);
      final listBefore = tester.state(
        find.byKey(const ValueKey('search-results')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byKey(const ValueKey('search-results'))),
        same(listBefore),
      );
      expect(find.byKey(const ValueKey('search-row-900')), findsOneWidget);
      expect(find.text('… earlier context clipped'), findsNothing);
      container(tester).read(searchControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byKey(const ValueKey('search-results'))),
        same(listBefore),
      );
      expect(find.byKey(const ValueKey('search-row-900')), findsOneWidget);
    },
  );

  testWidgets('dispose cancels progress polling and ignores late progress', (
    tester,
  ) async {
    final session = FixtureSearchSession(complete: false);
    session.pendingPoll = Completer<rust.SearchProgress>();
    final logs = SearchFixtureController();
    await mount(tester, logs, FixtureSearchBackend(logs, [session]));
    final search = container(tester).read(searchControllerProvider.notifier);
    search.setDraft('x');
    final pending = search.submit();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    session.pendingPoll!.complete(
      const rust.SearchProgress(
        totalMatches: 0,
        complete: false,
        cancelled: false,
        error: null,
      ),
    );
    await pending;
    await tester.pump(const Duration(seconds: 1));
    expect(session.polls, 1);
    expect(session.cancellations, 1);
    expect(tester.takeException(), isNull);
  });
}
