import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/search_model.dart';
import 'package:skyport/providers/search_controller.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;

import '../../helpers/search_fixture.dart';

void main() {
  late ProviderContainer container;
  late SearchFixtureController logs;
  late FixtureSearchBackend backend;
  late SearchController search;
  SearchBackend? snapshotBackend;

  setUp(() {
    logs = SearchFixtureController();
    snapshotBackend = null;
    backend = FixtureSearchBackend(logs, []);
    container = ProviderContainer(
      overrides: [
        uiControllerProvider.overrideWith(() => logs),
        uiSettingsProvider.overrideWith(SearchFixtureSettings.new),
        searchBackendProvider.overrideWith((ref) => snapshotBackend ?? backend),
      ],
    );
    container.read(uiControllerProvider);
    search = container.read(searchControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  FixtureSearchSession oneHit(int id, String text) => FixtureSearchSession(
    hits: [fixtureHit(id, 0, text.length)],
    views: {
      id: fixtureView(
        id,
        text,
        ranges: [const rust.SearchRange(start: 0, end: 1)],
      ),
    },
  );

  test(
    'draft/options are literal and only explicit submission starts work',
    () async {
      search.open();
      search.setDraft('  ');
      search.setCaseSensitive(false);
      final settings = container.read(uiSettingsProvider.notifier);
      settings.setHexDisplay(true);
      settings.setShowSent(false);
      settings.setEnableAnsi(true);
      expect(backend.submissions, isEmpty);
      backend.sessions.add(FixtureSearchSession());
      await search.submit();
      expect(backend.submissions.single.$1, '  ');
      final options = backend.submissions.single.$2;
      expect(options.hex, isTrue);
      expect(options.caseSensitive, isFalse);
      expect(options.showSent, isFalse);
      expect(options.stripAnsi, isTrue);
      search.setDraft('changed');
      expect(container.read(searchControllerProvider).activeQuery, '  ');
      expect(
        container.read(searchControllerProvider).dirty(search.currentOptions),
        isTrue,
      );
      search.close();
      search.open();
      expect(container.read(searchControllerProvider).draft, 'changed');
      expect(backend.submissions, hasLength(1));
    },
  );

  test(
    'navigation wraps global ranks including multiple hits in a record',
    () async {
      logs.upsert([fixtureRecord(1, 'xx')]);
      backend.sessions.add(
        FixtureSearchSession(
          hits: [fixtureHit(1, 0, 2), fixtureHit(1, 1, 2)],
          views: {1: fixtureView(1, 'xx')},
        ),
      );
      search.setDraft('x');
      await search.submit();
      expect(container.read(searchControllerProvider).selectedIndex, 0);
      await search.navigate(-1);
      expect(container.read(searchControllerProvider).selectedIndex, 1);
      expect(container.read(searchControllerProvider).wrapped, isTrue);
      await search.navigate(1);
      expect(container.read(searchControllerProvider).selectedIndex, 0);
      expect(container.read(searchControllerProvider).wrapped, isTrue);
    },
  );

  test('rapid navigation keeps every requested step', () async {
    logs.upsert([fixtureRecord(1, 'xxx')]);
    backend.sessions.add(
      FixtureSearchSession(
        hits: [fixtureHit(1, 0, 3), fixtureHit(1, 1, 3), fixtureHit(1, 2, 3)],
        views: {1: fixtureView(1, 'xxx')},
      ),
    );
    search.setDraft('x');
    await search.submit();
    final first = search.navigate(1);
    final second = search.navigate(1);
    await Future.wait([first, second]);
    expect(container.read(searchControllerProvider).selectedIndex, 2);
    final previous = search.navigate(-1);
    final previousAgain = search.navigate(-1);
    await Future.wait([previous, previousAgain]);
    expect(container.read(searchControllerProvider).selectedIndex, 0);
  });

  test(
    'first direction and manual scrolling use the visible text offset',
    () async {
      logs.upsert([fixtureRecord(1, 'x---x---x')]);
      backend.sessions.add(
        FixtureSearchSession(
          hits: [fixtureHit(1, 0, 9), fixtureHit(1, 1, 9), fixtureHit(1, 2, 9)],
          views: {
            1: fixtureView(
              1,
              'x---x---x',
              ranges: [
                const rust.SearchRange(start: 0, end: 1),
                const rust.SearchRange(start: 4, end: 5),
                const rust.SearchRange(start: 8, end: 9),
              ],
            ),
          },
        ),
      );
      var offset = 4;
      search.setPositionReader(() => (recordId: 1, offset: offset));
      search.setDraft('x');
      await search.navigate(-1);
      expect(container.read(searchControllerProvider).selectedIndex, 0);
      await search.navigate(1);
      expect(container.read(searchControllerProvider).selectedIndex, 1);
      offset = 7;
      search.userScrolled();
      await search.navigate(1);
      expect(container.read(searchControllerProvider).selectedIndex, 2);
      offset = 4;
      search.userScrolled();
      await search.submit();
      expect(container.read(searchControllerProvider).selectedIndex, 1);
      expect(backend.submissions, hasLength(1));
    },
  );

  testWidgets('pending anchor waits for the nearest hit rather than wrapping', (
    tester,
  ) async {
    logs.upsert([fixtureRecord(1, 'x'), fixtureRecord(3, 'x')]);
    final hits = [fixtureHit(1, 0, 1)];
    final session = FixtureSearchSession(
      hits: hits,
      views: {1: fixtureView(1, 'x'), 3: fixtureView(3, 'x')},
      complete: false,
    );
    backend.sessions.add(session);
    search.setPositionReader(() => (recordId: 2, offset: 0));
    search.setDraft('x');
    await search.submit();
    expect(container.read(searchControllerProvider).selectedHit, isNull);
    expect(container.read(searchControllerProvider).wrapped, isFalse);
    hits.add(fixtureHit(3, 1, 1));
    session.complete = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(searchControllerProvider).selectedHit!.recordId, 3);
    expect(container.read(searchControllerProvider).wrapped, isFalse);
  });

  testWidgets('rank navigation waits for a growing index before wrapping', (
    tester,
  ) async {
    logs.upsert([fixtureRecord(1, 'xx')]);
    final hits = [fixtureHit(1, 0, 2)];
    final session = FixtureSearchSession(
      hits: hits,
      views: {1: fixtureView(1, 'xx')},
      complete: false,
    );
    backend.sessions.add(session);
    search.setDraft('x');
    await search.submit();
    await search.navigate(1);
    expect(container.read(searchControllerProvider).selectedIndex, 0);
    expect(container.read(searchControllerProvider).wrapped, isFalse);
    hits.add(fixtureHit(1, 1, 2));
    session.complete = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(searchControllerProvider).selectedIndex, 1);
    expect(container.read(searchControllerProvider).wrapped, isFalse);
  });

  test('manual scrolling cancels an in-flight reveal', () async {
    logs.upsert([fixtureRecord(1, 'xx')]);
    final session = FixtureSearchSession(
      hits: [fixtureHit(1, 0, 2), fixtureHit(1, 1, 2)],
      views: {1: fixtureView(1, 'xx')},
    );
    backend.sessions.add(session);
    search.setDraft('x');
    await search.submit();
    session.pendingRecord = Completer<rust.SearchRecordView?>();
    final next = search.navigate(1);
    await Future<void>.delayed(Duration.zero);
    search.userScrolled();
    session.pendingRecord!.complete(fixtureView(1, 'xx'));
    await next;
    expect(container.read(searchControllerProvider).selectedIndex, 0);
  });

  test(
    'scrolling during submission prevents its captured position jumping back',
    () async {
      logs.upsert([fixtureRecord(1, 'x'), fixtureRecord(2, 'x')]);
      final accepted = Completer<FixtureSearchSession>();
      backend.onStart = (_, _) => accepted.future;
      var recordId = 1;
      search.setPositionReader(() => (recordId: recordId, offset: 0));
      search.setDraft('x');
      final submission = search.submit();
      recordId = 2;
      search.userScrolled();
      accepted.complete(
        FixtureSearchSession(
          hits: [fixtureHit(1, 0, 1), fixtureHit(2, 1, 1)],
          views: {1: fixtureView(1, 'x'), 2: fixtureView(2, 'x')},
        ),
      );
      await submission;
      expect(container.read(searchControllerProvider).selectedHit, isNull);
      await search.navigate(1);
      expect(container.read(searchControllerProvider).selectedHit!.recordId, 2);
    },
  );

  test(
    'invalid submit preserves active session and in-flight view request',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      final session = oneHit(1, 'x');
      backend.sessions.add(session);
      search.setDraft('x');
      await search.submit();
      session.pendingRecord = Completer<rust.SearchRecordView?>();
      final lookup = search.recordView(1);
      backend.onStart = (_, _) async => throw const rust.CoreError(
        kind: rust.ErrorKind.invalidArgument,
        message: 'invalid hex',
        bytesWritten: 0,
      );
      search.setDraft('invalid');
      await search.submit();
      session.pendingRecord!.complete(fixtureView(1, 'x'));
      expect(await lookup, isNotNull);
      expect(await search.recordView(1), isNotNull);
      expect(container.read(searchControllerProvider).activeQuery, 'x');
      expect(container.read(searchControllerProvider).error, isNotNull);
      expect(session.cancellations, 0);
    },
  );

  test(
    'invalid submit does not discard an in-flight accepted-session poll',
    () async {
      final session = FixtureSearchSession();
      session.pendingPoll = Completer<rust.SearchProgress>();
      backend.sessions.add(session);
      search.setDraft('old');
      final first = search.submit();
      await Future<void>.delayed(Duration.zero);
      backend.onStart = (_, _) async => throw StateError('rejected submission');
      search.setDraft('new');
      await search.submit();
      session.pendingPoll!.complete(
        const rust.SearchProgress(
          totalMatches: 0,
          complete: true,
          cancelled: false,
          error: null,
        ),
      );
      await first;
      expect(container.read(searchControllerProvider).activeQuery, 'old');
      expect(container.read(searchControllerProvider).complete, isTrue);
      expect(container.read(searchControllerProvider).error, isNotNull);
      expect(session.cancellations, 0);
    },
  );

  test(
    'inline pending valid start survives a newer rejected attempt',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      final accepted = Completer<FixtureSearchSession>();
      final session = oneHit(1, 'x');
      backend.onStart = (query, _) async {
        if (query == 'x') return accepted.future;
        throw StateError('rejected submission');
      };
      search.setDraft('x');
      final first = search.submit();
      expect(backend.submissions.single.$1, 'x');
      search.setDraft('invalid');
      final second = search.submit();
      await second;
      expect(backend.submissions, hasLength(2));
      accepted.complete(session);
      await first;
      expect(backend.submissions.map((entry) => entry.$1), ['x', 'invalid']);
      expect(container.read(searchControllerProvider).activeQuery, 'x');
      expect(container.read(searchControllerProvider).error, isNotNull);
      expect(session.cancellations, 0);
      expect(container.read(searchControllerProvider).submitting, isFalse);
      expect(await search.recordView(1), isNotNull);
    },
  );

  test(
    'append and later appended-record changes do not expand or invalidate snapshot',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      backend.sessions.add(oneHit(1, 'x'));
      search.setDraft('x');
      await search.submit();
      logs.upsert([fixtureRecord(2, 'x')]);
      logs.upsert([fixtureRecord(2, 'changed')]);
      logs.upsert([], removed: [2]);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      expect(container.read(searchControllerProvider).total, 1);
      logs.upsert([fixtureRecord(1, 'y')]);
      expect(container.read(searchControllerProvider).invalidated, isTrue);
      expect(container.read(searchControllerProvider).selectedHit, isNull);
    },
  );

  test(
    'pending recycled ID is invalidated by same timestamp/length replacement',
    () async {
      const pending = 0xFFFFFFFFFFFFFFFF;
      logs.upsert([fixtureRecord(pending, 'x')]);
      backend.sessions.add(oneHit(pending, 'x'));
      search.setDraft('x');
      await search.submit();
      logs.upsert([fixtureRecord(pending, 'y')]);
      expect(container.read(searchControllerProvider).invalidated, isTrue);
      expect(container.read(searchControllerProvider).total, 0);
    },
  );

  test(
    'new pending appended after submission does not invalidate snapshot',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      backend.sessions.add(oneHit(1, 'x'));
      search.setDraft('x');
      await search.submit();
      logs.upsert([fixtureRecord(0xFFFFFFFFFFFFFFFF, 'x')]);
      logs.upsert([fixtureRecord(0xFFFFFFFFFFFFFFFF, 'xx')]);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
    },
  );

  test('late submission reply cannot restore cleared results', () async {
    final pending = Completer<FixtureSearchSession>();
    backend.onStart = (_, _) => pending.future;
    search.setDraft('x');
    final submit = search.submit();
    await Future<void>.delayed(Duration.zero);
    search.clear();
    final session = FixtureSearchSession();
    pending.complete(session);
    await submit;
    expect(container.read(searchControllerProvider).activeQuery, isNull);
    expect(session.cancellations, 1);
    expect(session.polls, 0);
  });

  test('late record reply cannot restore cleared results', () async {
    logs.upsert([fixtureRecord(1, 'x')]);
    final session = oneHit(1, 'x');
    backend.sessions.add(session);
    search.setDraft('x');
    await search.submit();
    session.pendingRecord = Completer<rust.SearchRecordView?>();
    final lookup = search.recordView(1);
    search.clear();
    session.pendingRecord!.complete(fixtureView(1, 'x'));
    expect(await lookup, isNull);
    expect(container.read(searchControllerProvider).activeQuery, isNull);
  });

  test('empty explicit submit clears results and retains open bar', () async {
    backend.sessions.add(FixtureSearchSession());
    search.open();
    search.setDraft('x');
    await search.submit();
    search.setDraft('');
    await search.submit();
    expect(container.read(searchControllerProvider).activeQuery, isNull);
    expect(container.read(searchControllerProvider).visible, isTrue);
    expect(backend.submissions, hasLength(1));
  });

  test(
    'record identity mismatch is rejected, never rendered as current data',
    () async {
      logs.upsert([fixtureRecord(1, 'x', timestamp: 1)]);
      backend.sessions.add(oneHit(1, 'x'));
      search.setDraft('x');
      await search.submit();
      expect(container.read(searchControllerProvider).invalidated, isTrue);
    },
  );
  test(
    'oversized query rejection retains the last valid accepted session',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      final session = oneHit(1, 'x');
      backend.sessions.add(session);
      search.setDraft('x');
      await search.submit();
      backend.onStart = (_, _) async => throw const rust.CoreError(
        kind: rust.ErrorKind.invalidArgument,
        code: rust.ErrorCode.searchQueryTooLarge,
        message: 'query exceeds UTF-8 byte limit',
        bytesWritten: 0,
      );
      search.setDraft('😀' * 16385);
      await search.submit();
      final result = container.read(searchControllerProvider);
      expect(result.activeQuery, 'x');
      expect(result.selectedIndex, 0);
      expect(
        (result.error as rust.CoreError).code,
        rust.ErrorCode.searchQueryTooLarge,
      );
      expect(result.submitting, isFalse);
      expect(session.cancellations, 0);
      expect(await search.recordView(1), isNotNull);
    },
  );

  test('snapshot setup runs inline before another intent can append', () async {
    logs.upsert([fixtureRecord(1, 'x')]);
    final accepted = Completer<FixtureSearchSession>();
    backend.onStart = (_, _) => accepted.future;
    search.setDraft('x');
    final submit = search.submit();
    expect(backend.submissions.single.$1, 'x');
    logs.upsert([fixtureRecord(2, 'x')]);
    final session = oneHit(1, 'x');
    accepted.complete(session);
    await submit;
    expect(session.snapshotInfo.lastRecordId, 1);
    logs.upsert([fixtureRecord(2, 'changed')]);
    expect(container.read(searchControllerProvider).invalidated, isFalse);
  });

  test(
    'older successful completion cannot replace a newer accepted query',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      final older = Completer<FixtureSearchSession>();
      final newer = Completer<FixtureSearchSession>();
      backend.onStart = (query, _) =>
          query == 'old' ? older.future : newer.future;
      search.setDraft('old');
      final first = search.submit();
      search.setDraft('new');
      final second = search.submit();
      final newestSession = oneHit(1, 'x');
      newer.complete(newestSession);
      await second;
      final oldestSession = oneHit(1, 'x');
      older.complete(oldestSession);
      await first;
      expect(container.read(searchControllerProvider).activeQuery, 'new');
      expect(container.read(searchControllerProvider).submitting, isFalse);
      expect(oldestSession.cancellations, 1);
      expect(oldestSession.polls, 0);
      expect(newestSession.cancellations, 0);
    },
  );

  test(
    'older rejected completion cannot overwrite a newer accepted result',
    () async {
      final older = Completer<FixtureSearchSession>();
      backend.onStart = (query, _) async {
        if (query == 'old') return older.future;
        return FixtureSearchSession();
      };
      search.setDraft('old');
      final first = search.submit();
      search.setDraft('new');
      await search.submit();
      older.completeError(StateError('older rejection'));
      await first;
      expect(container.read(searchControllerProvider).activeQuery, 'new');
      expect(container.read(searchControllerProvider).error, isNull);
    },
  );

  test(
    'native snapshot waits for projection and uses actual native boundaries',
    () async {
      logs.upsert([fixtureRecord(1, 'old')]);
      final session = oneHit(2, 'x');
      snapshotBackend = _SnapshotBackend(
        session,
        const rust.SearchSnapshotInfo(
          sequence: 2,
          firstRecordId: 2,
          lastRecordId: 2,
          pending: null,
        ),
      );
      search.setDraft('x');
      final submit = search.submit();
      await Future<void>.delayed(Duration.zero);
      expect(session.polls, 0);
      expect(await search.recordView(2), isNull);
      logs.upsert([], removed: [1], sequence: 1);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      logs.upsert([fixtureRecord(2, 'x')], sequence: 2);
      await submit;
      expect(container.read(searchControllerProvider).selectedHit!.recordId, 2);
      logs.upsert([fixtureRecord(1, 'unrelated'), fixtureRecord(3, 'append')]);
      logs.upsert([], removed: [1, 3]);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      logs.upsert([fixtureRecord(2, 'y')]);
      expect(container.read(searchControllerProvider).invalidated, isTrue);
    },
  );

  test(
    'native pending snapshot arms identity only after projection catches up',
    () async {
      const pending = 0xFFFFFFFFFFFFFFFF;
      logs.upsert([fixtureRecord(pending, 'old')]);
      final session = FixtureSearchSession(
        hits: [fixtureHit(pending, 0, 1, timestamp: 2)],
        views: {pending: fixtureView(pending, 'x', timestamp: 2)},
      );
      snapshotBackend = _SnapshotBackend(
        session,
        rust.SearchSnapshotInfo(
          sequence: 3,
          firstRecordId: null,
          lastRecordId: null,
          pending: fixtureHit(pending, 0, 1, timestamp: 2),
        ),
      );
      search.setDraft('x');
      final submit = search.submit();
      await Future<void>.delayed(Duration.zero);
      logs.upsert([fixtureRecord(pending, 'intermediate')], sequence: 1);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      logs.upsert([fixtureRecord(pending, 'x', timestamp: 2)], sequence: 3);
      await submit;
      expect(container.read(searchControllerProvider).selectedHit, isNotNull);
      logs.upsert([fixtureRecord(pending, 'y', timestamp: 2)], sequence: 4);
      expect(container.read(searchControllerProvider).invalidated, isTrue);
    },
  );

  test(
    'changed pending metadata at catch-up invalidates before any lookup',
    () async {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final session = FixtureSearchSession();
      snapshotBackend = _SnapshotBackend(
        session,
        rust.SearchSnapshotInfo(
          sequence: 1,
          firstRecordId: null,
          lastRecordId: null,
          pending: fixtureHit(pending, 0, 1, timestamp: 2),
        ),
      );
      search.setDraft('x');
      final submit = search.submit();
      await Future<void>.delayed(Duration.zero);
      logs.upsert([fixtureRecord(pending, 'x', timestamp: 3)], sequence: 1);
      await submit;
      expect(container.read(searchControllerProvider).invalidated, isTrue);
      expect(session.polls, 0);
      expect(session.requestedViews, isEmpty);
      expect(session.cancellations, 1);
    },
  );

  test(
    'missing native boundary at catch-up invalidates before polling',
    () async {
      final session = FixtureSearchSession();
      snapshotBackend = _SnapshotBackend(
        session,
        const rust.SearchSnapshotInfo(
          sequence: 1,
          firstRecordId: 1,
          lastRecordId: 2,
          pending: null,
        ),
      );
      search.setDraft('x');
      final submit = search.submit();
      await Future<void>.delayed(Duration.zero);
      logs.upsert([fixtureRecord(2, 'x')], sequence: 1);
      await submit;
      expect(container.read(searchControllerProvider).invalidated, isTrue);
      expect(session.polls, 0);
    },
  );

  test(
    'filtered sent records are not members of the active snapshot',
    () async {
      logs.upsert([
        fixtureRecord(1, 'x'),
        fixtureRecord(2, 'sent', sent: true),
        fixtureRecord(3, 'x'),
        fixtureRecord(4, 'sent last', sent: true),
      ]);
      container.read(uiSettingsProvider.notifier).setShowSent(false);
      final session = oneHit(1, 'x');
      backend.sessions.add(session);
      search.setDraft('x');
      await search.submit();
      expect(session.snapshotInfo.firstRecordId, 1);
      expect(session.snapshotInfo.lastRecordId, 3);
      logs.upsert([fixtureRecord(2, 'changed', sent: true)]);
      logs.upsert([], removed: [2, 4]);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      logs.upsert([], removed: [1]);
      expect(container.read(searchControllerProvider).invalidated, isTrue);
    },
  );

  test(
    'empty native snapshot does not adopt records from the UI projection',
    () async {
      logs.upsert([fixtureRecord(1, 'x')]);
      final session = FixtureSearchSession();
      snapshotBackend = _SnapshotBackend(
        session,
        const rust.SearchSnapshotInfo(
          sequence: 0,
          firstRecordId: null,
          lastRecordId: null,
          pending: null,
        ),
      );
      search.setDraft('x');
      await search.submit();
      logs.upsert([fixtureRecord(1, 'changed')]);
      logs.upsert([], removed: [1]);
      expect(container.read(searchControllerProvider).invalidated, isFalse);
      expect(container.read(searchControllerProvider).total, 0);
    },
  );
}

class _SnapshotBackend implements SearchBackend {
  final FixtureSearchSession session;

  _SnapshotBackend(this.session, rust.SearchSnapshotInfo snapshot) {
    session.snapshotInfo = snapshot;
  }

  @override
  Future<SearchSession> start(String query, SearchConfiguration options) =>
      Future.value(session);
}
