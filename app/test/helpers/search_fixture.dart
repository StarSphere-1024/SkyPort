import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/search_model.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/search_controller.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;

class SearchFixtureController extends UiController {
  @override
  UiState build() => UiState(
    sequence: 0,
    connection: UiConnection.connected,
    portName: '',
    baudRate: 9600,
    dataBits: 8,
    parity: UiParity.none,
    flowControl: UiFlowControl.none,
    stopBits: 1,
    autoReconnect: false,
    hexSend: false,
    newline: UiNewline.none,
    autoSendEnabled: false,
    autoSendIntervalMs: 1000,
    logCapacityBytes: 16777216,
    sendHistory: const [],
    autoSendInput: '',
    ports: const [],
    rxBytes: 0,
    txBytes: 0,
    lastRxBytes: 0,
    error: null,
    logs: const LogState(),
    trimmedBytes: 0,
    trimmedRecords: 0,
    logIncomplete: false,
  );

  rust.SearchSnapshotInfo get snapshotInfo => snapshotInfoFor(showSent: true);

  rust.SearchSnapshotInfo snapshotInfoFor({required bool showSent}) {
    final included = state.logs.chunks.where(
      (chunk) => showSent || chunk.entries.first.type == LogEntryType.received,
    );
    final finalized = included.where((chunk) => chunk.id != 0xFFFFFFFFFFFFFFFF);
    final pending = included.lastOrNull?.id == 0xFFFFFFFFFFFFFFFF
        ? included.last
        : null;
    return rust.SearchSnapshotInfo(
      sequence: state.sequence,
      firstRecordId: finalized.firstOrNull?.id,
      lastRecordId: finalized.lastOrNull?.id,
      pending: pending == null
          ? null
          : fixtureHit(
              pending.id,
              0,
              pending.entries.first.data.length,
              timestamp: pending.entries.first.timestamp.millisecondsSinceEpoch,
            ),
    );
  }

  void upsert(
    List<rust.LogRecord> records, {
    List<int> removed = const [],
    int? sequence,
  }) {
    final delta = rust.LogDelta(
      upsert: records,
      removedIds: removed,
      earliestId: 0,
      totalBytes: 1000,
      trimmedBytes: 0,
      trimmedRecords: 0,
      incomplete: false,
    );
    state = sequence == null
        ? state.withLogDelta(delta)
        : state.withEvent(
            rust.Event(
              sequence: sequence,
              kind: rust.EventType.logChanged,
              log: delta,
            ),
          );
  }

  @override
  Future<void> clearLog() async {
    state = build();
  }
}

class SearchFixtureSettings extends UiSettingsNotifier {
  @override
  UiSettings build() => const UiSettings(showTimestamp: true, showSent: true);
  @override
  void setHexDisplay(bool value) => state = state.copyWith(hexDisplay: value);
  @override
  void setShowSent(bool value) => state = state.copyWith(showSent: value);
  @override
  void setEnableAnsi(bool value) => state = state.copyWith(enableAnsi: value);
}

class FixtureSearchBackend implements SearchBackend {
  final SearchFixtureController source;
  final List<(String, SearchConfiguration)> submissions = [];
  final List<FixtureSearchSession> sessions;
  Future<FixtureSearchSession> Function(String, SearchConfiguration)? onStart;

  FixtureSearchBackend(this.source, this.sessions);

  @override
  Future<SearchSession> start(String query, SearchConfiguration options) async {
    final snapshot = options.showSent
        ? source.snapshotInfo
        : source.snapshotInfoFor(showSent: false);
    submissions.add((query, options));
    final session = onStart == null
        ? sessions.removeAt(0)
        : await onStart!(query, options);
    session.snapshotInfo = snapshot;
    return session;
  }
}

class FixtureSearchSession implements SearchSession {
  @override
  late final rust.SearchSnapshotInfo snapshotInfo;
  final List<rust.SearchHit> hits;
  final Map<int, rust.SearchRecordView> views;
  final List<(int, int?)> requestedViews = [];
  Completer<rust.SearchProgress>? pendingPoll;
  Completer<rust.SearchRecordView?>? pendingRecord;
  bool complete;
  int polls = 0;
  int cancellations = 0;

  FixtureSearchSession({
    this.hits = const [],
    this.views = const {},
    this.complete = true,
  });

  @override
  Future<rust.SearchProgress> poll() async {
    polls++;
    if (pendingPoll != null) return pendingPoll!.future;
    return rust.SearchProgress(
      totalMatches: hits.length,
      complete: complete,
      cancelled: false,
      error: null,
    );
  }

  @override
  Future<rust.SearchHit?> match(int index) async =>
      index >= 0 && index < hits.length ? hits[index] : null;

  @override
  Future<rust.SearchRecordView?> record(int id, {int? focusIndex}) async {
    requestedViews.add((id, focusIndex));
    if (pendingRecord != null) return pendingRecord!.future;
    return views[id];
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

rust.LogRecord fixtureRecord(
  int id,
  String text, {
  bool sent = false,
  int timestamp = 0,
}) => rust.LogRecord(
  id: id,
  timestampMs: timestamp,
  direction: sent ? rust.Direction.sent : rust.Direction.received,
  data: Uint8List.fromList(utf8.encode(text)),
  pending: id == 0xFFFFFFFFFFFFFFFF,
);
rust.SearchHit fixtureHit(
  int id,
  int index,
  int sourceLength, {
  int timestamp = 0,
}) => rust.SearchHit(
  recordId: id,
  timestampMs: timestamp,
  sourceLength: sourceLength,
  index: index,
);

rust.SearchRecordView fixtureView(
  int id,
  String text, {
  int? sourceLength,
  int timestamp = 0,
  List<rust.SearchRange> ranges = const [],
  rust.SearchRange? focus,
  bool leadingClipped = false,
  bool trailingClipped = false,
}) => rust.SearchRecordView(
  recordId: id,
  timestampMs: timestamp,
  sourceLength: sourceLength ?? utf8.encode(text).length,
  text: text,
  ranges: ranges,
  focusRange: focus,
  leadingClipped: leadingClipped,
  trailingClipped: trailingClipped,
);
