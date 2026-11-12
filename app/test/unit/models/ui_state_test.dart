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
  rust.PendingAppend? pendingAppend,
}) => rust.LogDelta(
  upsert: rows,
  pendingAppend: pendingAppend,
  removedIds: removed,
  earliestId: earliest,
  totalBytes: bytes,
  trimmedBytes: 0,
  trimmedRecords: 0,
  incomplete: false,
);

List<LogEntry> records(LogState logs) =>
    logs.chunks.expand((chunk) => chunk.entries).toList();

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
    'snapshot history resumes across block eviction with a pending tail',
    () {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final initial = UiState.fromSnapshot(
        rust.AppSnapshot(
          sequence: 7,
          config: config,
          connection: rust.ConnectionState.connected,
          ports: const [],
          rxBytes: 257,
          txBytes: 1,
          lastRxBytes: 1,
          rxBytesPerSecond: 0,
          log: rust.LogSnapshot(
            records: [
              for (var id = 1; id <= 257; id++)
                row(id, [id & 255], sent: id == 256),
              row(pending, [0xe4], pending: true),
            ],
            totalBytes: 258,
            trimmedBytes: 0,
            trimmedRecords: 0,
            incomplete: false,
          ),
          autoSendInput: '',
        ),
      );
      final resumed = initial.withLogDelta(
        delta(
          [
            row(258, [0, 255], sent: true),
          ],
          removed: [for (var id = 1; id <= 256; id++) id],
          earliest: 257,
          bytes: 5,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 1,
            data: Uint8List.fromList([0xb8]),
          ),
        ),
      );
      expect(records(resumed.logs).map((entry) => entry.id), [
        257,
        258,
        pending,
      ]);
      expect(records(resumed.logs).map((entry) => entry.data), [
        [1],
        [0, 255],
        [0xe4, 0xb8],
      ]);
      expect(resumed.logs.entryForId(256), isNull);
      expect(resumed.logs.entryForId(258)!.type, LogEntryType.sent);
      expect(records(initial.logs).map((entry) => entry.id), [
        for (var id = 1; id <= 257; id++) id,
        pending,
      ]);
      expect(initial.logs.entryForId(256)!.type, LogEntryType.sent);
      expect(initial.logs.entryForId(pending)!.data, [0xe4]);
    },
  );
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
        log: delta(
          [
            row(1, [1]),
          ],
          bytes: 2,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([2]),
          ),
        ),
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
          ],
          removed: [pending],
          earliest: 2,
          bytes: 4,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([5]),
          ),
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
          ],
          earliest: 4,
          bytes: 3,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([254]),
          ),
        ),
      ),
    ]);
    expect(records(state.logs).map((entry) => entry.id), [4, pending]);
    expect(records(state.logs).expand((entry) => entry.data), [0, 255, 254]);
    expect(state.sequence, 5);
    expect(state.rxBytes, 7);
    expect(state.txBytes, 1);
    expect(state.lastRxBytes, 3);
    expect(state.logs.totalBytes, 3);
  });
  test('batched appends preserve pending and trimmed row update indices', () {
    const pending = 0xFFFFFFFFFFFFFFFF;
    final initial = emptyState().withLogDelta(
      delta(
        [],
        bytes: 1,
        pendingAppend: rust.PendingAppend(
          timestampMs: 1700000000000,
          offset: 0,
          data: Uint8List.fromList([255]),
        ),
      ),
    );
    final appended = initial.withLogDelta(
      delta([
        for (var id = 1; id <= 300; id++) row(id, [id]),
      ], bytes: 301),
    );
    final updated = appended.withLogDelta(
      delta(
        [
          row(150, [0, 128]),
        ],
        bytes: 303,
        pendingAppend: rust.PendingAppend(
          timestampMs: 1700000000000,
          offset: 1,
          data: Uint8List.fromList([254]),
        ),
      ),
    );
    final trimmed = updated.withLogDelta(
      delta(
        [
          row(301, [301], sent: true),
          row(302, [302]),
        ],
        removed: [1, 2],
        earliest: 3,
        bytes: 303,
      ),
    );
    final finalState = trimmed.withLogDelta(
      delta(
        [
          row(299, [0]),
        ],
        earliest: 3,
        bytes: 305,
        pendingAppend: rust.PendingAppend(
          timestampMs: 1700000000000,
          offset: 2,
          data: Uint8List.fromList([253, 252]),
        ),
      ),
    );
    expect(records(finalState.logs).map((entry) => entry.id), [
      for (var id = 3; id <= 302; id++) id,
      pending,
    ]);
    expect(records(finalState.logs).expand((entry) => entry.data), [
      for (var id = 3; id <= 302; id++)
        if (id == 150) ...[0, 128] else if (id == 299) 0 else id & 0xff,
      255,
      254,
      253,
      252,
    ]);
    expect(finalState.logs.chunks.last.isPending, isTrue);
    expect(finalState.logs.chunks.last.entries, hasLength(1));
    expect(finalState.logs.entryForId(301)!.type, LogEntryType.sent);
    expect(records(initial.logs).single.data, [255]);
    expect(records(appended.logs).elementAt(149).data, [150]);
    expect(records(updated.logs).last.data, [255, 254]);
    expect(records(updated.logs).elementAt(149).data, [0, 128]);
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
      expect(records(failed.logs).map((entry) => entry.id), [1, 2]);
    },
  );
  test(
    'metadata transitions preserve received rows and an observable subscription gap',
    () {
      const expectedApplied = (
        portName: '/dev/example',
        baudRate: 115200,
        dataBits: 8,
        parity: UiParity.even,
        stopBits: 1,
      );
      final initial = UiState.fromSnapshot(
        rust.AppSnapshot(
          sequence: 7,
          config: config,
          appliedConfig: config.serial,
          connection: rust.ConnectionState.connected,
          ports: const [
            rust.PortInfo(portName: '/dev/example', product: 'Adapter'),
          ],
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
      expect(initial.appliedConfig, expectedApplied);
      final reconfiguring = initial.withEvent(
        rust.Event(
          sequence: 8,
          kind: rust.EventType.stateChanged,
          state: rust.AppState(
            sequence: 8,
            config: config,
            connection: rust.ConnectionState.reconfiguring,
            appliedConfig: config.serial,
            ports: const [
              rust.PortInfo(portName: '/dev/example', product: 'Adapter'),
            ],
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
      expect(records(initial.logs).single.data, [0, 255]);
      final disconnected = received.withEvent(
        const rust.Event(sequence: 10, kind: rust.EventType.disconnected),
      );
      expect(disconnected.appliedConfig, isNull);
    },
  );
  test(
    'batched tails extend snapshot bytes once and preserve TX and CRLF order',
    () {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final prefix = emptyState().withLogDelta(
        delta(
          [],
          bytes: 2,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([0, 0xe4]),
          ),
        ),
      );
      final state = prefix.withEvents([
        rust.Event(
          sequence: 1,
          kind: rust.EventType.dataReceived,
          log: delta(
            [],
            bytes: 3,
            pendingAppend: rust.PendingAppend(
              timestampMs: 1700000000000,
              offset: 2,
              data: Uint8List.fromList([0xb8]),
            ),
          ),
        ),
        rust.Event(
          sequence: 2,
          kind: rust.EventType.dataSent,
          log: delta([
            row(1, [65], sent: true),
          ], bytes: 4),
        ),
        rust.Event(
          sequence: 3,
          kind: rust.EventType.dataReceived,
          log: delta(
            [],
            bytes: 6,
            pendingAppend: rust.PendingAppend(
              timestampMs: 1700000000000,
              offset: 3,
              data: Uint8List.fromList([0xad, 13]),
            ),
          ),
        ),
      ]);
      expect(records(state.logs).map((entry) => entry.id), [1, pending]);
      expect(records(state.logs).last.data, [0, 0xe4, 0xb8, 0xad, 13]);
      expect(records(prefix.logs).single.data, [0, 0xe4]);
      final completed = state.withLogDelta(
        delta(
          [
            row(2, [0, 0xe4, 0xb8, 0xad]),
          ],
          removed: [pending],
          bytes: 6,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000001,
            offset: 0,
            data: Uint8List.fromList([0xff]),
          ),
        ),
      );
      expect(records(completed.logs).map((entry) => entry.id), [1, 2, pending]);
      expect(records(completed.logs)[1].data, [0, 0xe4, 0xb8, 0xad]);
      expect(records(completed.logs).last.data, [0xff]);
      expect(records(state.logs).last.data, [0, 0xe4, 0xb8, 0xad, 13]);
    },
  );

  test('pending appends reject offset and timestamp discontinuities', () {
    final state = emptyState().withLogDelta(
      delta(
        [],
        bytes: 1,
        pendingAppend: rust.PendingAppend(
          timestampMs: 1700000000000,
          offset: 0,
          data: Uint8List.fromList([13]),
        ),
      ),
    );
    expect(
      () => state.withLogDelta(
        delta(
          [],
          bytes: 2,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 2,
            data: Uint8List.fromList([10]),
          ),
        ),
      ),
      throwsStateError,
    );
    expect(
      () => state.withLogDelta(
        delta(
          [],
          bytes: 2,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000001,
            offset: 1,
            data: Uint8List.fromList([10]),
          ),
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'TX and finalized RX retain wire bytes and pending order without mutating prior frames',
    () {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final receiving = emptyState().withLogDelta(
        delta(
          [],
          bytes: 2,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([0, 255]),
          ),
        ),
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
      expect(records(sent.logs).map((entry) => entry.id), [1, pending]);
      expect(sent.txBytes, 1);
      expect(records(receiving.logs).single.data, [0, 255]);
      final finalized = sent.withLogDelta(
        delta(
          [
            row(2, [0, 255]),
          ],
          removed: [pending],
          bytes: 4,
          pendingAppend: rust.PendingAppend(
            timestampMs: 1700000000000,
            offset: 0,
            data: Uint8List.fromList([254]),
          ),
        ),
      );
      expect(records(finalized.logs).map((entry) => entry.id), [1, 2, pending]);
      expect(records(finalized.logs)[1].data, [0, 255]);
      expect(records(finalized.logs).last.data, [254]);
      expect(records(sent.logs).last.data, [0, 255]);
      final trimmed = finalized.withLogDelta(delta([], earliest: 2, bytes: 3));
      expect(records(trimmed.logs).map((entry) => entry.id), [2, pending]);
      final cleared = trimmed.withLogDelta(
        delta([], removed: [2, pending], earliest: 3, bytes: 0),
      );
      expect(cleared.logs.chunks, isEmpty);
      expect(records(finalized.logs).map((entry) => entry.id), [1, 2, pending]);
    },
  );
}
