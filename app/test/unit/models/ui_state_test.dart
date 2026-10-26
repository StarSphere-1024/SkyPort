import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/src/rust/api.dart' as rust;

const config = rust.AppConfig(
  version: 1,
  serial: rust.SerialConfig(
    portName: '/dev/example',
    baudRate: 115200,
    dataBits: 8,
    parity: rust.Parity.even,
    flowControl: rust.FlowControl.none,
    stopBits: 1,
    autoReconnect: false,
  ),
  send: rust.SendSettings(
    hex: true,
    newline: rust.Newline.crLf,
    appendNewline: true,
    autoSendEnabled: false,
    autoSendIntervalMs: 10,
  ),
  logCapacityBytes: 16777216,
  history: ['41'],
);
UiState emptyState() => UiState(
  sequence: 0,
  connection: UiConnection.connected,
  portName: '/dev/example',
  baudRate: 9600,
  dataBits: 8,
  parity: UiParity.none,
  flowControl: UiFlowControl.none,
  stopBits: 1,
  autoReconnect: false,
  hexSend: false,
  newline: UiNewline.lf,
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

rust.LogRecord row(
  int id,
  List<int> data, {
  bool pending = false,
  bool sent = false,
}) => rust.LogRecord(
  id: id,
  timestampMs: 1700000000000,
  direction: sent ? rust.Direction.sent : rust.Direction.received,
  data: Uint8List.fromList(data),
  pending: pending,
);
rust.LogDelta delta(
  List<rust.LogRecord> rows, {
  List<int> removed = const [],
  int earliest = 1,
  required int bytes,
}) => rust.LogDelta(
  upsert: rows,
  removedIds: removed,
  earliestId: earliest,
  totalBytes: bytes,
  trimmedBytes: 0,
  trimmedRecords: 0,
  incomplete: false,
);

rust.Event stateChanged(
  int sequence,
  rust.ConnectionState connection, {
  rust.CoreError? error,
}) => rust.Event(
  sequence: sequence,
  kind: rust.EventType.stateChanged,
  state: rust.AppState(
    sequence: sequence,
    config: config,
    connection: connection,
    ports: const [],
    rxBytes: 0,
    txBytes: 0,
    lastRxBytes: 0,
    rxBytesPerSecond: 0,
    autoSendInput: '',
    error: error,
  ),
);

void main() {
  test(
    'retry diagnostics cannot hide partial writes or replay loss notices',
    () {
      const lost = rust.CoreError(
        kind: rust.ErrorKind.disconnected,
        message: 'device removed',
        bytesWritten: 0,
      );
      const retry = rust.CoreError(
        kind: rust.ErrorKind.openFailed,
        message: 'device absent',
        bytesWritten: 0,
      );
      const partial = rust.CoreError(
        kind: rust.ErrorKind.timeout,
        message: 'write deadline',
        bytesWritten: 2,
      );
      final disconnected = emptyState().withEvents([
        stateChanged(1, rust.ConnectionState.reconnecting, error: lost),
        const rust.Event(
          sequence: 2,
          kind: rust.EventType.disconnected,
          error: lost,
        ),
      ]);
      expect(disconnected.errorNotices, [(error: lost, reconnecting: true)]);
      final retrying = disconnected.withEvents([
        stateChanged(3, rust.ConnectionState.reconnecting, error: retry),
        const rust.Event(sequence: 4, kind: rust.EventType.reconnecting),
      ]);
      expect(retrying.error, retry);
      expect(
        identical(retrying.errorNotices, disconnected.errorNotices),
        isTrue,
      );

      final failed = retrying.withEvents([
        const rust.Event(
          sequence: 5,
          kind: rust.EventType.writeFailed,
          requestId: 7,
          error: partial,
        ),
        stateChanged(6, rust.ConnectionState.reconnecting, error: retry),
      ]);
      expect(failed.error, retry);
      expect(failed.errorNotices.single.error.bytesWritten, 2);
      expect(failed.errorNotices.single.reconnecting, isFalse);
      final recovered = failed.withEvent(
        stateChanged(7, rust.ConnectionState.connected),
      );
      expect(recovered.error, isNull);
      expect(identical(recovered.errorNotices, failed.errorNotices), isTrue);
    },
  );

  test(
    'manual connect failures notify once per attempt, even if identical',
    () {
      const error = rust.CoreError(
        kind: rust.ErrorKind.openFailed,
        message: 'device absent',
        bytesWritten: 0,
      );
      var state = emptyState();
      List<UiErrorNotice>? previous;
      for (var attempt = 0; attempt < 2; attempt++) {
        final sequence = attempt * 4;
        state = state.withEvents([
          stateChanged(sequence + 1, rust.ConnectionState.connecting),
          stateChanged(
            sequence + 2,
            rust.ConnectionState.disconnected,
            error: error,
          ),
          rust.Event(
            sequence: sequence + 3,
            kind: rust.EventType.disconnected,
            error: error,
          ),
          rust.Event(
            sequence: sequence + 4,
            kind: rust.EventType.commandFailed,
            requestId: attempt + 1,
            error: error,
          ),
        ]);
        expect(state.errorNotices, [(error: error, reconnecting: false)]);
        expect(identical(state.errorNotices, previous), isFalse);
        previous = state.errorNotices;
      }
      final stopped = state.withEvents([
        stateChanged(9, rust.ConnectionState.disconnecting),
        stateChanged(10, rust.ConnectionState.disconnected),
      ]);
      expect(identical(stopped.errorNotices, previous), isTrue);
      expect(stopped.error, isNull);
    },
  );

  test('event batches do not resurrect trimmed or cleared pending rows', () {
    const pending = 0xFFFFFFFFFFFFFFFF;
    final state = emptyState().withEvents([
      rust.Event(
        sequence: 1,
        kind: rust.EventType.dataReceived,
        rxBytes: 2,
        lastRxBytes: 2,
        log: delta([
          row(1, [1]),
          row(pending, [2], pending: true),
        ], bytes: 2),
      ),
      rust.Event(
        sequence: 2,
        kind: rust.EventType.dataSent,
        txBytes: 1,
        log: delta([
          row(2, [3], sent: true),
        ], bytes: 3),
      ),
      rust.Event(
        sequence: 3,
        kind: rust.EventType.dataReceived,
        rxBytes: 4,
        lastRxBytes: 2,
        log: delta(
          [
            row(3, [2, 4]),
            row(pending, [5], pending: true),
          ],
          removed: [pending],
          earliest: 2,
          bytes: 4,
        ),
      ),
      rust.Event(
        sequence: 4,
        kind: rust.EventType.logChanged,
        log: delta([], removed: [2, 3, pending], earliest: 4, bytes: 0),
      ),
      rust.Event(
        sequence: 5,
        kind: rust.EventType.dataReceived,
        rxBytes: 7,
        lastRxBytes: 3,
        log: delta(
          [
            row(4, [0, 255]),
            row(pending, [254], pending: true),
          ],
          earliest: 4,
          bytes: 3,
        ),
      ),
    ]);
    expect(state.logs.chunks.map((chunk) => chunk.id), [4, pending]);
    expect(state.logs.chunks.expand((chunk) => chunk.entries.single.data), [
      0,
      255,
      254,
    ]);
    expect(state.sequence, 5);
    expect(state.rxBytes, 7);
    expect(state.txBytes, 1);
    expect(state.lastRxBytes, 3);
    expect(state.logs.totalBytes, 3);
  });
  test('batched appends preserve pending and trimmed row update indices', () {
    const pending = 0xFFFFFFFFFFFFFFFF;
    final initial = emptyState().withLogDelta(
      delta([
        row(pending, [255], pending: true),
      ], bytes: 1),
    );
    final appended = initial.withLogDelta(
      delta([
        for (var id = 1; id <= 100; id++) row(id, [id]),
      ], bytes: 101),
    );
    final updated = appended.withLogDelta(
      delta([
        row(50, [0, 128]),
        row(pending, [254], pending: true),
      ], bytes: 102),
    );
    final trimmed = updated.withLogDelta(
      delta(
        [
          row(101, [101], sent: true),
          row(102, [102]),
        ],
        removed: [1, 2],
        earliest: 3,
        bytes: 102,
      ),
    );
    final finalState = trimmed.withLogDelta(
      delta(
        [
          row(99, [0]),
          row(pending, [253, 252], pending: true),
        ],
        earliest: 3,
        bytes: 103,
      ),
    );
    expect(finalState.logs.chunks.map((chunk) => chunk.id), [
      for (var id = 3; id <= 102; id++) id,
      pending,
    ]);
    expect(
      finalState.logs.chunks.expand((chunk) => chunk.entries.single.data),
      [
        for (var id = 3; id <= 102; id++)
          if (id == 50) ...[0, 128] else if (id == 99) 0 else id,
        253,
        252,
      ],
    );
    expect(finalState.logs.chunks[98].entries.single.type, LogEntryType.sent);
    expect(initial.logs.chunks.single.entries.single.data, [255]);
    expect(appended.logs.chunks[49].entries.single.data, [50]);
    expect(updated.logs.chunks.last.entries.single.data, [254]);
  });
  test(
    'partial-write failures and port scans cannot erase received data or double-count TX',
    () {
      var state = emptyState().withEvent(
        rust.Event(
          sequence: 1,
          kind: rust.EventType.dataReceived,
          rxBytes: 2,
          lastRxBytes: 2,
          log: delta([
            row(1, [0, 255]),
          ], bytes: 2),
        ),
      );
      state = state.withEvent(
        rust.Event(
          sequence: 2,
          kind: rust.EventType.dataSent,
          requestId: 0,
          txBytes: 2,
          log: delta([
            row(2, [65, 66], sent: true),
          ], bytes: 4),
        ),
      );
      state = state.withEvent(
        const rust.Event(
          sequence: 3,
          kind: rust.EventType.writeFailed,
          requestId: 1,
          error: rust.CoreError(
            kind: rust.ErrorKind.timeout,
            message: 'write deadline',
            bytesWritten: 2,
          ),
        ),
      );
      final failed = state;
      state = state.withEvent(
        const rust.Event(
          sequence: 4,
          kind: rust.EventType.portsChanged,
          ports: [],
        ),
      );
      expect(state.txBytes, 2);
      expect(state.rxBytes, 2);
      expect(state.error!.kind, rust.ErrorKind.timeout);
      state = state.withBridgeError(
        const rust.CoreError(
          kind: rust.ErrorKind.internal,
          message: 'bridge unavailable',
          bytesWritten: 0,
        ),
      );
      expect(state.connection, UiConnection.connected);
      expect(state.txBytes, 2);
      expect(state.rxBytes, 2);
      expect(
        state.logs.chunks
            .expand((chunk) => chunk.entries)
            .expand((entry) => entry.data),
        [0, 255, 65, 66],
      );
      state = state.withDataGap(true);
      state = state.withEvent(
        rust.Event(
          sequence: 5,
          kind: rust.EventType.logChanged,
          log: delta([], removed: [1, 2], earliest: 3, bytes: 0),
        ),
      );
      expect(state.logs.chunks, isEmpty);
      expect(
        state.dataGap,
        isTrue,
      ); // Log deltas cannot acknowledge a display gap.
      state = state.withDataGap(false);
      expect(state.dataGap, isFalse);
      expect(failed.logs.chunks.map((chunk) => chunk.id), [1, 2]);
    },
  );
  test(
    'metadata transitions preserve received rows and an observable subscription gap',
    () {
      final initial = UiState.fromSnapshot(
        rust.AppSnapshot(
          sequence: 7,
          config: config,
          connection: rust.ConnectionState.connected,
          ports: const ['/dev/example'],
          rxBytes: 2,
          txBytes: 1,
          lastRxBytes: 2,
          rxBytesPerSecond: 0,
          log: rust.LogSnapshot(
            records: [
              row(1, [0, 255]),
            ],
            totalBytes: 2,
            trimmedBytes: 10,
            trimmedRecords: 1,
            incomplete: true,
          ),
          autoSendInput: '41',
        ),
        dataGap: true,
      );
      final reconfiguring = initial.withEvent(
        const rust.Event(
          sequence: 8,
          kind: rust.EventType.stateChanged,
          state: rust.AppState(
            sequence: 8,
            config: config,
            connection: rust.ConnectionState.reconfiguring,
            ports: ['/dev/example'],
            rxBytes: 2,
            txBytes: 1,
            lastRxBytes: 2,
            rxBytesPerSecond: 0,
            autoSendInput: '41',
          ),
        ),
      );
      final received = reconfiguring.withEvent(
        rust.Event(
          sequence: 9,
          kind: rust.EventType.dataReceived,
          rxBytes: 3,
          lastRxBytes: 1,
          log: delta([
            row(2, [254]),
          ], bytes: 3),
        ),
      );
      expect(received.connection, UiConnection.reconfiguring);
      expect(
        received.logs.chunks
            .expand((chunk) => chunk.entries)
            .expand((entry) => entry.data),
        [0, 255, 254],
      );
      expect(received.rxBytes, 3);
      expect(received.txBytes, 1);
      expect(received.dataGap, isTrue);
      expect(initial.logIncomplete, isTrue);
      expect(initial.trimmedBytes, 10);
      expect(initial.logs.chunks.single.entries.single.data, [0, 255]);
    },
  );
  test(
    'TX and finalized RX retain wire bytes and pending order without mutating prior frames',
    () {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final receiving = emptyState().withLogDelta(
        delta([
          row(pending, [0, 255], pending: true),
        ], bytes: 2),
      );
      final sent = receiving.withEvent(
        rust.Event(
          sequence: 2,
          kind: rust.EventType.dataSent,
          txBytes: 1,
          requestId: 1,
          data: Uint8List.fromList([65]),
          log: delta([
            row(1, [65], sent: true),
          ], bytes: 3),
        ),
      );
      expect(sent.logs.chunks.map((chunk) => chunk.id), [1, pending]);
      expect(sent.txBytes, 1);
      expect(receiving.logs.chunks.single.entries.single.data, [0, 255]);
      final finalized = sent.withLogDelta(
        delta(
          [
            row(2, [0, 255]),
            row(pending, [254], pending: true),
          ],
          removed: [pending],
          bytes: 4,
        ),
      );
      expect(finalized.logs.chunks.map((chunk) => chunk.id), [1, 2, pending]);
      expect(finalized.logs.chunks[1].entries.single.data, [0, 255]);
      expect(finalized.logs.chunks.last.entries.single.data, [254]);
      expect(sent.logs.chunks.last.entries.single.data, [0, 255]);
      final trimmed = finalized.withLogDelta(delta([], earliest: 2, bytes: 3));
      expect(trimmed.logs.chunks.map((chunk) => chunk.id), [2, pending]);
      final cleared = trimmed.withLogDelta(
        delta([], removed: [2, pending], earliest: 3, bytes: 0),
      );
      expect(cleared.logs.chunks, isEmpty);
      expect(finalized.logs.chunks.map((chunk) => chunk.id), [1, 2, pending]);
    },
  );
}
