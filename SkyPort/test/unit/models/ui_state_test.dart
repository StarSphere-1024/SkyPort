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
  chunkIndices: const {},
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

void main() {
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
