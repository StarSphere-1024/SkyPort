import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_model.dart';
import '../models/search_model.dart';
import '../src/rust/api.dart' as rust;
import 'ui_controller.dart';
import 'ui_settings_provider.dart';

/// Tests replace this intent boundary, never a native opaque handle.
abstract interface class SearchBackend {
  Future<SearchSession> start(String query, SearchConfiguration options);
}

abstract interface class SearchSession {
  rust.SearchSnapshotInfo get snapshotInfo;
  Future<rust.SearchProgress> poll();
  Future<rust.SearchHit?> match(int index);
  Future<rust.SearchRecordView?> record(int id, {int? focusIndex});
  Future<void> cancel();
}

final searchBackendProvider = Provider<SearchBackend>(
  (ref) => _NativeSearchBackend(ref.read(uiControllerProvider.notifier)),
);

class _NativeSearchBackend implements SearchBackend {
  final UiController controller;
  _NativeSearchBackend(this.controller);

  @override
  Future<SearchSession> start(String query, SearchConfiguration options) async {
    final pending = controller.startSearch(query, options.toRust());
    final reply = await pending;
    if (reply.error != null) throw reply.error!;
    return _NativeSearchSession(reply.search!, reply.snapshot!);
  }
}

class _NativeSearchSession implements SearchSession {
  final rust.SearchHandle handle;
  @override
  final rust.SearchSnapshotInfo snapshotInfo;
  _NativeSearchSession(this.handle, this.snapshotInfo);

  @override
  Future<rust.SearchProgress> poll() => rust.pollSearch(search: handle);
  @override
  Future<rust.SearchHit?> match(int index) async {
    final reply = await rust.searchMatch(search: handle, index: index);
    if (reply.error != null) throw reply.error!;
    return reply.hit;
  }

  @override
  Future<rust.SearchRecordView?> record(int id, {int? focusIndex}) async {
    final reply = await rust.searchRecord(
      search: handle,
      recordId: id,
      focusIndex: focusIndex,
    );
    if (reply.error != null) throw reply.error!;
    return reply.record;
  }

  @override
  Future<void> cancel() => rust.cancelSearch(search: handle);
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  SearchSession? _session;
  Timer? _timer;
  bool _disposed = false;
  int _generation = 0;
  int _navigation = 0;
  int? _requestedIndex;
  int _submission = 0;
  int _lifecycle = 0;
  int _acceptedSubmission = 0;
  int? _pollingGeneration;
  int? _snapshotFirst;
  int? _snapshotLast;
  LogChunk? _snapshotPending;
  rust.SearchSnapshotInfo? _snapshotInfo;
  bool _snapshotReady = false;
  Completer<void>? _snapshotWaiter;
  final _views = <(int, int?), rust.SearchRecordView?>{};
  final _requests = <(int, int?), Future<rust.SearchRecordView?>>{};

  @override
  SearchState build() {
    ref.listen(uiControllerProvider, (previous, next) {
      if (_session == null) return;
      if (!_snapshotReady) {
        if (next.sequence >= _snapshotInfo!.sequence) _armSnapshot(next.logs);
        return;
      }
      if (previous != null &&
          _recordsChanged(
            previous.logs,
            next.logs,
            first: _snapshotFirst,
            last: _snapshotLast,
            pending: _snapshotPending,
            showSent: state.options!.showSent,
          )) {
        invalidate();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _releaseSnapshotWaiter();
      _timer?.cancel();
      final session = _session;
      if (session != null) unawaited(session.cancel());
      _session = null;
      _views.clear();
      _requests.clear();
    });
    return const SearchState();
  }

  SearchConfiguration get currentOptions {
    final settings = ref.read(uiSettingsProvider);
    return SearchConfiguration(
      hex: settings.hexDisplay,
      caseSensitive: state.caseSensitive,
      showSent: settings.showSent,
      stripAnsi: settings.enableAnsi,
    );
  }

  void open() => state = state.copyWith(visible: true);
  void close() => state = state.copyWith(visible: false);
  void setDraft(String value) => state = state.copyWith(draft: value);
  void setCaseSensitive(bool value) =>
      state = state.copyWith(caseSensitive: value);

  Future<void> submit() async {
    if (state.draft.isEmpty) {
      clear();
      return;
    }
    final query = state.draft;
    final options = currentOptions;
    final submission = ++_submission;
    final lifecycle = _lifecycle;
    _timer?.cancel();
    state = state.copyWith(submitting: true, clearError: true, wrapped: false);
    // Native setup runs synchronously inside start, before this intent yields.
    // Fake backends may finish out of order; only accepted successes supersede.
    final generation = await _acceptSubmission(
      query,
      options,
      submission,
      lifecycle,
    );
    if (generation != null) await _poll(generation);
  }

  Future<int?> _acceptSubmission(
    String query,
    SearchConfiguration options,
    int submission,
    int lifecycle,
  ) async {
    if (_disposed || lifecycle != _lifecycle) return null;
    try {
      final session = await ref
          .read(searchBackendProvider)
          .start(query, options);
      if (_disposed ||
          lifecycle != _lifecycle ||
          submission < _acceptedSubmission) {
        await session.cancel();
        return null;
      }
      _acceptedSubmission = submission;
      final old = _session;
      final generation = ++_generation;
      _releaseSnapshotWaiter();
      _snapshotInfo = session.snapshotInfo;
      _snapshotFirst = session.snapshotInfo.firstRecordId;
      _snapshotLast = session.snapshotInfo.lastRecordId;
      _snapshotPending = null;
      _snapshotReady = false;
      _session = session;
      _requestedIndex = null;
      if (old != null) unawaited(old.cancel());
      _views.clear();
      _requests.clear();
      state = state.copyWith(
        activeQuery: query,
        options: options,
        submitting: submission == _submission ? false : state.submitting,
        complete: false,
        invalidated: false,
        total: 0,
        clearError: submission == _submission,
        clearSelection: true,
        generation: generation,
      );
      final projection = ref.read(uiControllerProvider);
      if (projection.sequence >= session.snapshotInfo.sequence) {
        _armSnapshot(projection.logs);
      } else {
        final waiter = Completer<void>();
        _snapshotWaiter = waiter;
        await waiter.future;
      }
      if (_disposed || generation != _generation || !_snapshotReady) {
        return null;
      }
      return generation;
    } catch (error) {
      if (_disposed || lifecycle != _lifecycle || submission != _submission) {
        return null;
      }
      state = state.copyWith(submitting: false, error: error);
      if (_session != null && !state.complete) {
        _timer = Timer(
          const Duration(milliseconds: 100),
          () => _poll(_generation),
        );
      } else if (state.selectedIndex == null && state.total > 0) {
        await navigate(0);
      }
      return null;
    }
  }

  Future<void> _poll(int generation) async {
    final session = _session;
    if (session == null ||
        _disposed ||
        generation != _generation ||
        !_snapshotReady) {
      return;
    }
    if (_pollingGeneration == generation) return;
    _pollingGeneration = generation;
    try {
      final progress = await session.poll();
      if (_disposed || generation != _generation) return;
      if (progress.error != null) throw progress.error!;
      if (progress.cancelled) {
        if (state.submitting) return;
        invalidate();
        return;
      }
      state = state.copyWith(
        total: progress.totalMatches,
        complete: progress.complete,
      );
      if (progress.complete) {
        _timer?.cancel();
        _timer = null;
      }
      if (state.selectedIndex == null && state.total > 0) await navigate(0);
      if (!_disposed && generation == _generation && !progress.complete) {
        _timer = Timer(
          const Duration(milliseconds: 100),
          () => _poll(generation),
        );
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(error: error, complete: true);
      }
    } finally {
      if (_pollingGeneration == generation) _pollingGeneration = null;
    }
  }

  Future<void> navigate(int direction) async {
    final session = _session;
    if (session == null ||
        state.total == 0 ||
        state.invalidated ||
        state.submitting ||
        !_snapshotReady) {
      return;
    }
    final generation = _generation;
    final navigation = ++_navigation;
    final base = _requestedIndex ?? state.selectedIndex;
    final raw = base == null ? 0 : base + direction;
    final index = raw % state.total;
    _requestedIndex = index;
    try {
      final hit = await session.match(index);
      if (_disposed || generation != _generation || navigation != _navigation) {
        return;
      }
      if (hit == null ||
          !_isCurrent(hit.recordId, hit.timestampMs, hit.sourceLength)) {
        invalidate();
        return;
      }
      final view = await recordView(hit.recordId, focusIndex: index);
      if (_disposed || generation != _generation || navigation != _navigation) {
        return;
      }
      if (view == null) {
        invalidate();
        return;
      }
      state = state.copyWith(
        selectedIndex: index,
        selectedHit: hit,
        selectedView: view,
        wrapped: raw < 0 || raw >= state.total,
        navigation: navigation,
      );
    } catch (error) {
      if (!_disposed &&
          generation == _generation &&
          navigation == _navigation) {
        state = state.copyWith(error: error);
      }
    }
  }

  Future<rust.SearchRecordView?> recordView(int id, {int? focusIndex}) {
    final key = (id, focusIndex);
    if (_views.containsKey(key)) {
      final value = _views.remove(key);
      _views[key] = value;
      return Future.value(value);
    }
    final existing = _requests[key];
    if (existing != null) return existing;
    final session = _session;
    if (session == null || state.invalidated || !_snapshotReady) {
      return Future.value();
    }
    final generation = _generation;
    if (_requests.length >= 48) {
      // Backpressure native lookups during rapid viewport movement.
      return _requests.values.first.then<rust.SearchRecordView?>((_) {
        if (_disposed || generation != _generation) return null;
        return recordView(id, focusIndex: focusIndex);
      });
    }
    final request = session
        .record(id, focusIndex: focusIndex)
        .then<rust.SearchRecordView?>(
          (view) {
            if (_disposed || generation != _generation) return null;
            if (view != null &&
                !_isCurrent(
                  view.recordId,
                  view.timestampMs,
                  view.sourceLength,
                )) {
              invalidate();
              return null;
            }
            if (_views.length >= 48) _views.remove(_views.keys.first);
            _views[key] = view;
            return view;
          },
          onError: (Object error, StackTrace stack) {
            if (!_disposed && generation == _generation) {
              state = state.copyWith(error: error);
            }
            return null;
          },
        )
        .whenComplete(() {
          if (generation == _generation) _requests.remove(key);
        });
    // Both retained views and outstanding work are bounded by the lazy viewport.
    _requests[key] = request;
    return request;
  }

  bool _isCurrent(int id, int timestamp, int length) {
    final chunks = ref.read(uiControllerProvider).logs.chunks;
    final index = LogChunk.insertionIndex(chunks, id);
    if (index == chunks.length || chunks[index].id != id) return false;
    final entry = chunks[index].entries.first;
    return entry.timestamp.millisecondsSinceEpoch == timestamp &&
        entry.data.length == length;
  }

  void _armSnapshot(LogState logs) {
    final info = _snapshotInfo!;
    bool contains(int id) {
      final index = LogChunk.insertionIndex(logs.chunks, id);
      return index < logs.chunks.length && logs.chunks[index].id == id;
    }

    if ((_snapshotFirst != null && !contains(_snapshotFirst!)) ||
        (_snapshotLast != null && !contains(_snapshotLast!))) {
      invalidate();
      return;
    }
    final pending = info.pending;
    if (pending != null) {
      if (!_isCurrent(
        pending.recordId,
        pending.timestampMs,
        pending.sourceLength,
      )) {
        invalidate();
        return;
      }
      final index = LogChunk.insertionIndex(logs.chunks, pending.recordId);
      _snapshotPending = logs.chunks[index];
    }
    _snapshotReady = true;
    _releaseSnapshotWaiter();
  }

  void _releaseSnapshotWaiter() {
    final waiter = _snapshotWaiter;
    _snapshotWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  static bool _recordsChanged(
    LogState previous,
    LogState next, {
    int? first,
    int? last,
    LogChunk? pending,
    required bool showSent,
  }) {
    if (identical(previous, next)) return false;
    // Immutable chunks are reused on identical upserts. Only records belonging
    // to this snapshot matter, not records appended after explicit submission.
    var cursor = 0;
    for (final old in previous.chunks) {
      if (!showSent && old.entries.first.type == LogEntryType.sent) continue;
      final retained = old.id == 0xFFFFFFFFFFFFFFFF
          ? identical(old, pending)
          : first != null && last != null && old.id >= first && old.id <= last;
      if (!retained) continue;
      while (cursor < next.chunks.length && next.chunks[cursor].id != old.id) {
        cursor++;
      }
      if (cursor == next.chunks.length ||
          !identical(old, next.chunks[cursor])) {
        return true;
      }
      cursor++;
    }
    return false;
  }

  void invalidate() {
    _cancel();
    state = state.copyWith(
      invalidated: true,
      submitting: false,
      complete: true,
      total: 0,
      clearSelection: true,
      generation: _generation,
    );
  }

  void clear() {
    _cancel();
    state = SearchState(
      visible: state.visible,
      draft: state.draft,
      caseSensitive: state.caseSensitive,
      generation: _generation,
    );
  }

  void _cancel() {
    _generation++;
    _submission++;
    _lifecycle++;
    _navigation++;
    _requestedIndex = null;
    _releaseSnapshotWaiter();
    _snapshotInfo = null;
    _snapshotReady = false;
    _timer?.cancel();
    _timer = null;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.cancel());
    _views.clear();
    _snapshotFirst = null;
    _snapshotLast = null;
    _snapshotPending = null;
    _requests.clear();
  }
}
