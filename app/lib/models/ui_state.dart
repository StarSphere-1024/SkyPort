import 'dart:typed_data';

import 'package:skyport/src/rust/api.dart' as rust;

import 'log_model.dart';

enum UiConnection {
  disconnected,
  connecting,
  connected,
  reconfiguring,
  disconnecting,
  reconnecting,
  closing,
  closed,
}

enum UiParity { none, odd, even }

enum UiFlowControl { none, hardware, software }

enum UiNewline { none, lf, cr, crlf }

typedef UiErrorNotice = ({rust.CoreError error, bool reconnecting});

class UiState {
  final int sequence;
  final UiConnection connection;
  final String portName;
  final int baudRate;
  final int dataBits;
  final UiParity parity;
  final UiFlowControl flowControl;
  final int stopBits;
  final bool autoReconnect;
  final bool hexSend;
  final UiNewline newline;
  final bool appendNewline;
  final bool autoSendEnabled;
  final int autoSendIntervalMs;
  final int logCapacityBytes;
  final List<String> sendHistory;
  final String autoSendInput;
  final List<String> ports;
  final int rxBytes;
  final int txBytes;
  final int lastRxBytes;
  final double rxBytesPerSecond;
  final rust.CoreError? error;
  final rust.CoreError? autoSendError;
  final List<UiErrorNotice> errorNotices;
  final LogState logs;
  final int trimmedBytes;
  final int trimmedRecords;
  final bool logIncomplete;
  final bool dataGap;

  UiState({
    required this.sequence,
    required this.connection,
    required this.portName,
    required this.baudRate,
    required this.dataBits,
    required this.parity,
    required this.flowControl,
    required this.stopBits,
    required this.autoReconnect,
    required this.hexSend,
    required this.newline,
    this.appendNewline = false,
    required this.autoSendEnabled,
    required this.autoSendIntervalMs,
    required this.logCapacityBytes,
    required this.sendHistory,
    required this.autoSendInput,
    required this.ports,
    required this.rxBytes,
    required this.txBytes,
    required this.lastRxBytes,
    this.rxBytesPerSecond = 0,
    required this.error,
    this.autoSendError,
    this.errorNotices = const [],
    required this.logs,
    required this.trimmedBytes,
    required this.trimmedRecords,
    required this.logIncomplete,
    this.dataGap = false,
  });

  factory UiState.fromSnapshot(
    rust.AppSnapshot snapshot, {
    bool dataGap = false,
  }) {
    final chunks = <LogChunk>[];
    for (final record in snapshot.log.records) {
      chunks.add(_chunk(record));
    }
    return UiState(
      sequence: snapshot.sequence,
      connection: _connection(snapshot.connection),
      portName: snapshot.config.serial.portName,
      baudRate: snapshot.config.serial.baudRate,
      dataBits: snapshot.config.serial.dataBits,
      parity: _parity(snapshot.config.serial.parity),
      stopBits: snapshot.config.serial.stopBits,
      flowControl: _flowControl(snapshot.config.serial.flowControl),
      autoReconnect: snapshot.config.serial.autoReconnect,
      hexSend: snapshot.config.send.hex,
      newline: _newline(snapshot.config.send.newline),
      appendNewline: snapshot.config.send.appendNewline,
      autoSendEnabled: snapshot.config.send.autoSendEnabled,
      autoSendIntervalMs: snapshot.config.send.autoSendIntervalMs,
      logCapacityBytes: snapshot.config.logCapacityBytes,
      sendHistory: snapshot.config.history,
      autoSendInput: snapshot.autoSendInput,
      ports: snapshot.ports,
      rxBytes: snapshot.rxBytes,
      txBytes: snapshot.txBytes,
      lastRxBytes: snapshot.lastRxBytes,
      rxBytesPerSecond: snapshot.rxBytesPerSecond,
      error: snapshot.error,
      autoSendError: snapshot.autoSendError,
      logs: LogState(chunks: chunks, totalBytes: snapshot.log.totalBytes),
      trimmedBytes: snapshot.log.trimmedBytes,
      trimmedRecords: snapshot.log.trimmedRecords,
      logIncomplete: snapshot.log.incomplete,
      dataGap: dataGap,
    );
  }

  UiState withState(rust.AppState update) => UiState(
    sequence: update.sequence,
    connection: _connection(update.connection),
    portName: update.config.serial.portName,
    baudRate: update.config.serial.baudRate,
    dataBits: update.config.serial.dataBits,
    parity: _parity(update.config.serial.parity),
    stopBits: update.config.serial.stopBits,
    autoReconnect: update.config.serial.autoReconnect,
    flowControl: _flowControl(update.config.serial.flowControl),
    hexSend: update.config.send.hex,
    newline: _newline(update.config.send.newline),
    appendNewline: update.config.send.appendNewline,
    autoSendEnabled: update.config.send.autoSendEnabled,
    autoSendIntervalMs: update.config.send.autoSendIntervalMs,
    logCapacityBytes: update.config.logCapacityBytes,
    sendHistory: update.config.history,
    autoSendInput: update.autoSendInput,
    ports: update.ports,
    rxBytes: update.rxBytes,
    txBytes: update.txBytes,
    rxBytesPerSecond: update.rxBytesPerSecond,
    lastRxBytes: update.lastRxBytes,
    error: update.error,
    autoSendError: update.autoSendError,
    errorNotices: errorNotices,
    logs: logs,
    trimmedBytes: trimmedBytes,
    trimmedRecords: trimmedRecords,
    logIncomplete: logIncomplete,
    dataGap: dataGap,
  );

  UiState withEvent(rust.Event event) => withEvents([event]);

  UiState withEvents(Iterable<rust.Event> events) {
    var next = this;
    final deltas = <rust.LogDelta>[];
    List<UiErrorNotice>? notices;
    for (final event in events) {
      if (event.sequence <= next.sequence) continue;
      switch (event.kind) {
        case rust.EventType.stateChanged:
          final update = event.state;
          if (update != null) {
            if (next.connection == UiConnection.connected &&
                (update.connection == rust.ConnectionState.reconnecting ||
                    update.connection == rust.ConnectionState.disconnected) &&
                update.error != null) {
              (notices ??= []).add((
                error: update.error!,
                reconnecting:
                    update.connection == rust.ConnectionState.reconnecting,
              ));
            }
            next = next.withState(update);
          }
        case rust.EventType.portsChanged:
          next = next._copy(sequence: event.sequence, ports: event.ports);
        case rust.EventType.logChanged:
        case rust.EventType.dataReceived:
        case rust.EventType.dataSent:
          if (event.log != null) deltas.add(event.log!);
          next = next._copy(
            sequence: event.sequence,
            rxBytes: event.rxBytes,
            lastRxBytes: event.lastRxBytes,
            txBytes: event.txBytes,
          );
        case rust.EventType.disconnected:
          next = next._copy(
            sequence: event.sequence,
            error: event.error,
            replaceError: true,
          );
        case rust.EventType.writeFailed:
        case rust.EventType.queueOverflow:
        case rust.EventType.taskFailed:
        case rust.EventType.commandFailed:
          next = next._copy(
            sequence: event.sequence,
            error: event.error,
            replaceError: true,
          );
          if (event.error != null) {
            (notices ??= []).add((error: event.error!, reconnecting: false));
          }
        case rust.EventType.reconnecting:
        case rust.EventType.commandCompleted:
          next = next._copy(sequence: event.sequence);
      }
    }
    if (notices != null) next = next._copy(errorNotices: notices);
    if (deltas.isEmpty) return next;
    if (deltas.length == 1) return next.withLogDelta(deltas.single);

    final upsert = <int, rust.LogRecord>{};
    final removed = <int>{};
    for (final delta in deltas) {
      for (final id in delta.removedIds) {
        upsert.remove(id);
        removed.add(id);
      }
      for (final record in delta.upsert) {
        removed.remove(record.id);
        upsert[record.id] = record;
      }
    }
    final last = deltas.last;
    return next.withLogDelta(
      rust.LogDelta(
        upsert: [
          for (final record in upsert.values)
            if (record.id == 0xFFFFFFFFFFFFFFFF || record.id >= last.earliestId)
              record,
        ],
        removedIds: removed.toList(),
        earliestId: last.earliestId,
        totalBytes: last.totalBytes,
        trimmedBytes: last.trimmedBytes,
        trimmedRecords: last.trimmedRecords,
        incomplete: last.incomplete,
      ),
    );
  }

  UiState withLogDelta(rust.LogDelta delta, {int? sequence}) {
    // ponytail: O(retained rows) metadata copies are capped at 65,536; group immutable chunks if measured jank.
    final chunks = List<LogChunk>.of(logs.chunks);
    final removed = delta.removedIds.isEmpty
        ? const <int>{}
        : delta.removedIds.toSet();
    if (removed.isNotEmpty ||
        (chunks.isNotEmpty &&
            chunks.first.id != 0xFFFFFFFFFFFFFFFF &&
            chunks.first.id < delta.earliestId)) {
      chunks.removeWhere((chunk) {
        final remove =
            removed.contains(chunk.id) ||
            (chunk.id != 0xFFFFFFFFFFFFFFFF && chunk.id < delta.earliestId);
        if (remove) LogEntry.evictCachedData(chunk.entries);
        return remove;
      });
    }

    for (final record in delta.upsert) {
      final index = LogChunk.insertionIndex(chunks, record.id);
      final exists = index < chunks.length && chunks[index].id == record.id;
      if (exists && _sameRecord(chunks[index].entries.first, record)) {
        continue;
      }
      if (exists) LogEntry.evictCachedData(chunks[index].entries);
      final chunk = _chunk(record);
      if (exists) {
        chunks[index] = chunk;
      } else {
        chunks.insert(index, chunk);
      }
    }
    return _copy(
      sequence: sequence ?? this.sequence,
      logs: LogState(chunks: chunks, totalBytes: delta.totalBytes),
      trimmedBytes: delta.trimmedBytes,
      trimmedRecords: delta.trimmedRecords,
      logIncomplete: delta.incomplete,
    );
  }

  UiState withDataGap(bool value) => _copy(dataGap: value);
  UiState withBridgeError(rust.CoreError value) => _copy(
    error: value,
    replaceError: true,
    errorNotices: [(error: value, reconnecting: false)],
  );

  UiState _copy({
    int? sequence,
    List<String>? ports,
    int? rxBytes,
    int? txBytes,
    int? lastRxBytes,
    bool replaceError = false,
    rust.CoreError? error,
    LogState? logs,
    List<UiErrorNotice>? errorNotices,
    int? trimmedBytes,
    int? trimmedRecords,
    bool? logIncomplete,
    bool? dataGap,
  }) => UiState(
    sequence: sequence ?? this.sequence,
    connection: connection,
    portName: portName,
    baudRate: baudRate,
    dataBits: dataBits,
    parity: parity,
    stopBits: stopBits,
    flowControl: flowControl,
    autoReconnect: autoReconnect,
    hexSend: hexSend,
    newline: newline,
    appendNewline: appendNewline,
    logCapacityBytes: logCapacityBytes,
    sendHistory: sendHistory,
    autoSendEnabled: autoSendEnabled,
    autoSendIntervalMs: autoSendIntervalMs,
    autoSendInput: autoSendInput,
    ports: ports ?? this.ports,
    rxBytes: rxBytes ?? this.rxBytes,
    txBytes: txBytes ?? this.txBytes,
    lastRxBytes: lastRxBytes ?? this.lastRxBytes,
    rxBytesPerSecond: rxBytesPerSecond,
    error: replaceError ? error : this.error,
    autoSendError: autoSendError,
    errorNotices: errorNotices ?? this.errorNotices,
    logs: logs ?? this.logs,
    trimmedBytes: trimmedBytes ?? this.trimmedBytes,
    trimmedRecords: trimmedRecords ?? this.trimmedRecords,
    logIncomplete: logIncomplete ?? this.logIncomplete,
    dataGap: dataGap ?? this.dataGap,
  );

  static LogChunk _chunk(rust.LogRecord record) {
    final entry = LogEntry(
      Uint8List.fromList(record.data),
      record.direction == rust.Direction.sent
          ? LogEntryType.sent
          : LogEntryType.received,
      DateTime.fromMillisecondsSinceEpoch(record.timestampMs),
      id: record.id,
    );
    return LogChunk(entries: [entry], id: record.id);
  }

  static bool _sameRecord(LogEntry entry, rust.LogRecord record) {
    if (entry.type !=
            (record.direction == rust.Direction.sent
                ? LogEntryType.sent
                : LogEntryType.received) ||
        entry.timestamp.millisecondsSinceEpoch != record.timestampMs ||
        entry.data.length != record.data.length) {
      return false;
    }
    for (var i = 0; i < entry.data.length; i++) {
      if (entry.data[i] != record.data[i]) return false;
    }
    return true;
  }

  static UiConnection _connection(rust.ConnectionState value) =>
      switch (value) {
        rust.ConnectionState.disconnected => UiConnection.disconnected,
        rust.ConnectionState.connecting => UiConnection.connecting,
        rust.ConnectionState.connected => UiConnection.connected,
        rust.ConnectionState.reconfiguring => UiConnection.reconfiguring,
        rust.ConnectionState.disconnecting => UiConnection.disconnecting,
        rust.ConnectionState.reconnecting => UiConnection.reconnecting,
        rust.ConnectionState.closing => UiConnection.closing,
        rust.ConnectionState.closed => UiConnection.closed,
      };
  static UiParity _parity(rust.Parity value) => switch (value) {
    rust.Parity.none => UiParity.none,
    rust.Parity.odd => UiParity.odd,
    rust.Parity.even => UiParity.even,
  };
  static UiFlowControl _flowControl(rust.FlowControl value) => switch (value) {
    rust.FlowControl.none => UiFlowControl.none,
    rust.FlowControl.hardware => UiFlowControl.hardware,
    rust.FlowControl.software => UiFlowControl.software,
  };
  static UiNewline _newline(rust.Newline value) => switch (value) {
    rust.Newline.none => UiNewline.none,
    rust.Newline.lf => UiNewline.lf,
    rust.Newline.cr => UiNewline.cr,
    rust.Newline.crLf => UiNewline.crlf,
  };
}
