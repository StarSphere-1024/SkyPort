import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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

  Future<void> pumpSearchFrames(WidgetTester tester) async {
    final list = find.byKey(const ValueKey('search-results'));
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final scrollable in tester.stateList<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      )) {
        final position = scrollable.position;
        expect(
          position.pixels,
          inInclusiveRange(
            position.minScrollExtent - 1,
            position.maxScrollExtent + 1,
          ),
          reason: 'search frame $frame must not overscroll and rebound',
        );
      }
    }
  }

  Rect focusedRect(WidgetTester tester) {
    final search = container(tester).read(searchControllerProvider);
    final view = search.selectedView!;
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byKey(
              ValueKey('search-row-${search.selectedHit!.recordId}'),
            ),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText().contains('needle'),
            ),
          )
          .first,
    );
    final prefix = paragraph.text.toPlainText().length - view.text.length;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: prefix + view.focusRange!.start,
        extentOffset: prefix + view.focusRange!.end,
      ),
    );
    var bounds = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      bounds = bounds.expandToInclude(box.toRect());
    }
    return MatrixUtils.transformRect(paragraph.getTransformTo(null), bounds);
  }

  void expectFocusVisible(WidgetTester tester) {
    final viewport = tester.getRect(
      find.byKey(const ValueKey('search-results')),
    );
    final focus = focusedRect(tester);
    expect(focus.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(focus.bottom, lessThanOrEqualTo(viewport.bottom + 1));
  }

  testWidgets(
    'search reveal stays bounded at the tail and preserves visible matches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final logs = SearchFixtureController();
      const ids = [1, 3, 40, 115, 118];
      String text(int id) => ids.contains(id) ? 'needle row $id' : 'row $id';
      const range = rust.SearchRange(start: 0, end: 6);
      final session = FixtureSearchSession(
        hits: [
          for (var index = 0; index < ids.length; index++)
            fixtureHit(ids[index], index, text(ids[index]).length),
        ],
        views: {
          for (final id in ids)
            id: fixtureView(id, text(id), ranges: [range], focus: range),
        },
      );
      await mount(tester, logs, FixtureSearchBackend(logs, [session]));
      logs.upsert([
        for (var id = 1; id <= 120; id++) fixtureRecord(id, text(id)),
      ]);
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('search-results'));
      await tester.drag(list, const Offset(0, 200));
      await tester.pumpAndSettle();
      tester
          .widget<ScrollablePositionedList>(list)
          .itemScrollController!
          .jumpTo(index: 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        'needle',
      );
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await pumpSearchFrames(tester);
      expectFocusVisible(tester);
      final first = find.byKey(const ValueKey('search-row-1'));
      final readingPosition = tester.getTopLeft(first);
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await pumpSearchFrames(tester);
      expect(container(tester).read(searchControllerProvider).selectedIndex, 1);
      expect(tester.getTopLeft(first), readingPosition);
      expectFocusVisible(tester);
      for (var index = 2; index < ids.length; index++) {
        await tester.tap(find.byKey(const ValueKey('search-next')));
        await pumpSearchFrames(tester);
        expect(
          container(tester).read(searchControllerProvider).selectedIndex,
          index,
        );
        expectFocusVisible(tester);
      }
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await pumpSearchFrames(tester);
      expect(container(tester).read(searchControllerProvider).selectedIndex, 0);
      expect(container(tester).read(searchControllerProvider).wrapped, isTrue);
      expectFocusVisible(tester);
      await tester.tap(find.byKey(const ValueKey('search-previous')));
      await pumpSearchFrames(tester);
      expect(container(tester).read(searchControllerProvider).selectedIndex, 4);
      expectFocusVisible(tester);
      final lastRow = find.byKey(const ValueKey('search-row-118'));
      final tailPosition = tester.getTopLeft(lastRow);
      await tester.tap(find.byKey(const ValueKey('search-previous')));
      await pumpSearchFrames(tester);
      expect(container(tester).read(searchControllerProvider).selectedIndex, 3);
      expect(tester.getTopLeft(lastRow), tailPosition);
      expectFocusVisible(tester);
    },
  );

  testWidgets('search reveal reaches matches deep inside a single long record', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final logs = SearchFixtureController();
    final text = List.generate(
      60,
      (line) =>
          '${line == 0 || line == 55 ? 'needle' : 'line'} $line ${'wrapped ' * 4}',
    ).join('\n');
    final session = _LongRecordSession(text);
    await mount(tester, logs, FixtureSearchBackend(logs, [session]));
    logs.upsert([fixtureRecord(1, text)]);
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('search-results'));
    await tester.drag(list, const Offset(0, 200));
    await tester.pumpAndSettle();
    tester
        .widget<ScrollablePositionedList>(list)
        .itemScrollController!
        .jumpTo(index: 0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('search-input')),
      'needle',
    );
    for (final index in [0, 1, 0]) {
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await pumpSearchFrames(tester);
      expect(
        container(tester).read(searchControllerProvider).selectedIndex,
        index,
      );
      expectFocusVisible(tester);
    }
  });

  testWidgets('search reveal includes the last line of a multiline match', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final logs = SearchFixtureController();
    const text = 'needle\nneedle';
    const range = rust.SearchRange(start: 0, end: text.length);
    final session = FixtureSearchSession(
      hits: [fixtureHit(2, 0, text.length)],
      views: {
        2: fixtureView(2, text, ranges: [range], focus: range),
      },
    );
    await mount(tester, logs, FixtureSearchBackend(logs, [session]));
    logs.upsert([
      fixtureRecord(1, 'before\n' * 40),
      fixtureRecord(2, text),
      fixtureRecord(3, 'after\n' * 40),
    ]);
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('search-results'));
    await tester.drag(list, const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-open')));
    await tester.pumpAndSettle();
    tester
        .widget<ScrollablePositionedList>(list)
        .itemScrollController!
        .jumpTo(index: 1, alignment: 0.9);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('search-row-2'))).bottom,
      greaterThan(tester.getRect(list).bottom),
    );
    final search = container(tester).read(searchControllerProvider.notifier);
    search.setDraft(text);
    await search.submit();
    await pumpSearchFrames(tester);
    expect(container(tester).read(searchControllerProvider).selectedIndex, 0);
    expectFocusVisible(tester);
  });

  testWidgets(
    'typing preserves reading; Enter advances matches; Esc preserves draft',
    (tester) async {
      final logs = SearchFixtureController();
      const query = '  literal  ';
      final text = query * 2;
      final backend = FixtureSearchBackend(logs, [
        FixtureSearchSession(
          hits: [fixtureHit(1, 0, text.length), fixtureHit(1, 1, text.length)],
          views: {
            1: fixtureView(
              1,
              text,
              ranges: [
                rust.SearchRange(start: 0, end: query.length),
                rust.SearchRange(start: query.length, end: text.length),
              ],
            ),
          },
        ),
      ]);
      await mount(tester, logs, backend);
      logs.upsert([fixtureRecord(1, text)]);
      await tester.pumpAndSettle();
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
      expect(container(tester).read(searchControllerProvider).selectedIndex, 0);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(container(tester).read(searchControllerProvider).selectedIndex, 1);
      await tester.enterText(input, 'new draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'new draft');
      expect(backend.submissions, hasLength(1));
      final toggle = find.byKey(const ValueKey('search-open'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'new draft');
      expect(backend.submissions, hasLength(1));
    },
  );

  testWidgets(
    'narrow attached bar submits through navigation and applies dirty options',
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
      await tester.tap(find.byKey(const ValueKey('search-next')));
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
      await tester.tap(find.byKey(const ValueKey('search-previous')));
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

  testWidgets(
    'following after search keeps every frame in bounds and yields to scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(550, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final logs = SearchFixtureController();
      String text(int id) =>
          'row $id ${id % 30 < 15 ? 'wrapped MQTT data ' * 12 : 'short'}';
      final session = FixtureSearchSession(
        hits: [fixtureHit(1, 0, text(1).length)],
        views: {1: fixtureView(1, text(1))},
      );
      await mount(tester, logs, FixtureSearchBackend(logs, [session]));
      logs.upsert([
        for (var id = 1; id <= 150; id++) fixtureRecord(id, text(id)),
      ]);
      await tester.pumpAndSettle();
      final search = container(tester).read(searchControllerProvider.notifier);
      search.open();
      search.setDraft('row');
      await search.submit();
      await tester.pumpAndSettle();
      search.close();
      search.clear();
      await tester.pumpAndSettle();

      final list = find.byKey(const ValueKey('search-results'));
      Future<void> pumpBoundedFrames() async {
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          for (final scrollable in tester.stateList<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )) {
            final position = scrollable.position;
            expect(
              position.pixels,
              inInclusiveRange(
                position.minScrollExtent - 1,
                position.maxScrollExtent + 1,
              ),
              reason: 'frame $frame must not overscroll and rebound',
            );
          }
        }
      }

      await tester.tap(find.byType(FloatingActionButton));
      await pumpBoundedFrames();
      for (var id = 151; id <= 185; id++) {
        logs.upsert([fixtureRecord(id, text(id))]);
        await pumpBoundedFrames();
        final latest = find.byKey(ValueKey('search-row-$id'));
        expect(latest, findsOneWidget);
        expect(
          tester.getBottomRight(latest).dy,
          closeTo(tester.getBottomRight(list).dy - 8, 1),
        );
      }

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(list),
          scrollDelta: const Offset(0, -200),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final anchor = find.byKey(const ValueKey('search-row-185'));
      final readingPosition = tester.getTopLeft(anchor);
      logs.upsert([fixtureRecord(186, text(186))]);
      await pumpBoundedFrames();
      expect(tester.getTopLeft(anchor), readingPosition);
      await tester.tap(find.byType(FloatingActionButton));
      await pumpBoundedFrames();
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('search-row-186'))).dy,
        closeTo(tester.getBottomRight(list).dy - 8, 1),
      );

      final tail = find.byKey(const ValueKey('search-row-186'));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: tail, matching: find.byType(RichText)).first,
      );
      final start = paragraph.text.toPlainText().indexOf('row 186');
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 7),
          )
          .first
          .toRect();
      final selection = await tester.startGesture(
        paragraph.localToGlobal(box.centerLeft + const Offset(0.1, 0)),
        kind: PointerDeviceKind.mouse,
      );
      await selection.moveTo(
        paragraph.localToGlobal(box.centerRight - const Offset(0.1, 0)),
      );
      await selection.up();
      await tester.pumpAndSettle();
      final selectedPosition = tester.getTopLeft(tail);
      logs.upsert([fixtureRecord(187, text(187))]);
      await pumpBoundedFrames();
      expect(tester.getTopLeft(tail), selectedPosition);

      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, 'row 186');

      await logs.clearLog();
      await tester.pumpAndSettle();
      logs.upsert([fixtureRecord(1, 'short output')]);
      await pumpBoundedFrames();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('search-row-1'))).dy,
        closeTo(tester.getTopLeft(list).dy + 8, 1),
      );
    },
  );

  testWidgets(
    'navigation anchors in the middle of a wrapped row and reanchors after scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final logs = SearchFixtureController();
      final text = List.generate(
        40,
        (index) => 'needle$index ${'payload ' * 5}',
      ).join('\n');
      final starts = [
        for (var index = 0; index < 40; index++) text.indexOf('needle$index'),
      ];
      final ranges = [
        for (final start in starts)
          rust.SearchRange(start: start, end: start + 8),
      ];
      final session = FixtureSearchSession(
        hits: [
          for (var index = 0; index < starts.length; index++)
            fixtureHit(2, index, text.length),
        ],
        views: {2: fixtureView(2, text, ranges: ranges, focus: ranges.first)},
      );
      await mount(tester, logs, FixtureSearchBackend(logs, [session]));
      logs.upsert([fixtureRecord(1, 'before'), fixtureRecord(2, text)]);
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('search-results'));
      await tester.drag(list, const Offset(0, 220));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        'needle',
      );
      await tester.pump();

      int visibleOffset() {
        final row = find.byKey(const ValueKey('search-row-2'));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: row, matching: find.byType(RichText)).first,
        );
        final viewport = RenderAbstractViewport.of(paragraph) as RenderBox;
        final top = paragraph.globalToLocal(
          viewport.localToGlobal(Offset.zero),
        );
        final offset = paragraph.getPositionForOffset(Offset(0, top.dy)).offset;
        return (offset - 18).clamp(0, text.length).toInt();
      }

      int nextMatch(int offset) {
        final index = starts.indexWhere((start) => start >= offset);
        return index < 0 ? 0 : index;
      }

      int anchor = visibleOffset();
      expect(anchor, inInclusiveRange(0, text.length));
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await tester.pumpAndSettle();
      expect(
        container(tester).read(searchControllerProvider).selectedIndex,
        nextMatch(anchor),
      );

      await tester.drag(list, const Offset(0, 140));
      await tester.pumpAndSettle();
      anchor = visibleOffset();
      expect(anchor, inInclusiveRange(0, text.length));
      await tester.tap(find.byKey(const ValueKey('search-next')));
      await tester.pumpAndSettle();
      expect(
        container(tester).read(searchControllerProvider).selectedIndex,
        nextMatch(anchor),
      );
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

class _LongRecordSession extends FixtureSearchSession {
  _LongRecordSession(String text)
    : super(
        hits: [fixtureHit(1, 0, text.length), fixtureHit(1, 1, text.length)],
        views: {
          1: fixtureView(
            1,
            text,
            ranges: [
              const rust.SearchRange(start: 0, end: 6),
              rust.SearchRange(
                start: text.lastIndexOf('needle'),
                end: text.lastIndexOf('needle') + 6,
              ),
            ],
          ),
        },
      );

  @override
  Future<rust.SearchRecordView?> record(int id, {int? focusIndex}) async {
    final view = await super.record(id, focusIndex: focusIndex);
    if (view == null) return null;
    return fixtureView(
      id,
      view.text,
      ranges: view.ranges,
      focus: focusIndex == null ? null : view.ranges[focusIndex],
    );
  }
}
