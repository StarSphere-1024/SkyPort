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
typedef UiSerialConfig = ({
  String portName,
  int baudRate,
  int dataBits,
  UiParity parity,
  int stopBits,
});

class UiPort {
  const UiPort({
    required this.portName,
    this.product,
    this.manufacturer,
    this.serialNumber,
    this.vid,
    this.pid,
  });

  final String portName;
  final String? product;
  final String? manufacturer;
  final String? serialNumber;
  final int? vid;
  final int? pid;
}

class UiState {
  final int sequence;
  final UiConnection connection;
  final String portName;
  final UiSerialConfig? appliedConfig;
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
  final List<UiPort> ports;
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
    this.appliedConfig,
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
    var entries = <LogEntry>[];
    for (final record in snapshot.log.records) {
      if (record.id == 0xFFFFFFFFFFFFFFFF) {
        if (entries.isNotEmpty) {
          chunks.add(LogChunk(entries: entries));
          entries = <LogEntry>[];
        }
        chunks.add(LogChunk(entries: [_entry(record)]));
      } else {
        entries.add(_entry(record));
        if (entries.length == LogChunk.capacity) {
          chunks.add(LogChunk(entries: entries));
          entries = <LogEntry>[];
        }
      }
    }
    if (entries.isNotEmpty) chunks.add(LogChunk(entries: entries));
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
      ports: snapshot.ports.map(_uiPort).toList(),
      appliedConfig: _serialConfig(snapshot.appliedConfig),
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
    ports: update.ports.map(_uiPort).toList(),
    appliedConfig: _serialConfig(update.appliedConfig),
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
          next = next._copy(
            sequence: event.sequence,
            ports: event.ports?.map(_uiPort).toList(),
          );
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
            appliedConfig: null,
            replaceAppliedConfig: true,
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
    final appendBytes = BytesBuilder(copy: false);
    int? appendOffset;
    int? appendTimestamp;
    var pendingReset = false;
    for (final delta in deltas) {
      for (final id in delta.removedIds) {
        upsert.remove(id);
        removed.add(id);
        if (id == 0xFFFFFFFFFFFFFFFF) {
          appendBytes.clear();
          appendOffset = null;
          appendTimestamp = null;
          pendingReset = true;
        }
      }
      for (final record in delta.upsert) {
        upsert[record.id] = record;
      }
      final append = delta.pendingAppend;
      if (append != null) {
        final existing = pendingReset ? null : _existingPending();
        final expectedOffset = appendOffset == null
            ? (existing?.data.length ?? 0)
            : appendOffset + appendBytes.length;
        final expectedTimestamp =
            appendTimestamp ?? existing?.timestamp.millisecondsSinceEpoch;
        if (append.offset != expectedOffset ||
            (expectedTimestamp != null &&
                append.timestampMs != expectedTimestamp)) {
          throw StateError('Inconsistent pending log append');
        }
        appendOffset ??= append.offset;
        appendTimestamp ??= append.timestampMs;
        appendBytes.add(append.data);
        pendingReset = false;
      }
    }
    final last = deltas.last;
    final pendingAppend = appendOffset == null
        ? null
        : rust.PendingAppend(
            timestampMs: appendTimestamp!,
            offset: appendOffset,
            data: appendBytes.takeBytes(),
          );
    return next.withLogDelta(
      rust.LogDelta(
        upsert: [
          for (final record in upsert.values)
            if (record.id >= last.earliestId) record,
        ],
        removedIds: removed.toList(),
        earliestId: last.earliestId,
        totalBytes: last.totalBytes,
        trimmedBytes: last.trimmedBytes,
        trimmedRecords: last.trimmedRecords,
        incomplete: last.incomplete,
        pendingAppend: pendingAppend,
      ),
    );
  }

  UiState withLogDelta(rust.LogDelta delta, {int? sequence}) {
    const pendingId = 0xFFFFFFFFFFFFFFFF;
    final chunks = List<LogChunk>.of(logs.chunks);
    final edited = <LogChunk>{};
    List<LogEntry> writable(int index) {
      final chunk = chunks[index];
      if (edited.contains(chunk)) return chunk.entries;
      final copy = LogChunk(entries: List<LogEntry>.of(chunk.entries));
      chunks[index] = copy;
      edited.add(copy);
      return copy.entries;
    }

    final expired = LogChunk.insertionIndex(chunks, delta.earliestId);
    for (var index = 0; index < expired; index++) {
      LogEntry.evictCachedData(chunks[index].entries);
    }
    chunks.removeRange(0, expired);
    if (chunks.isNotEmpty &&
        !chunks.first.isPending &&
        chunks.first.firstId < delta.earliestId) {
      final first = chunks.first;
      final offset = first.indexOfId(delta.earliestId);
      LogEntry.evictCachedData(first.entries.take(offset));
      final retained = LogChunk(entries: first.entries.sublist(offset));
      chunks[0] = retained;
      edited.add(retained);
    }

    for (final id in delta.removedIds) {
      if (id != pendingId && id < delta.earliestId) continue;
      final index = id == pendingId
          ? chunks.length - 1
          : LogChunk.insertionIndex(chunks, id);
      if (index < 0 || index == chunks.length) continue;
      final chunk = chunks[index];
      final offset = chunk.indexOfId(id);
      if (offset == chunk.entries.length || chunk.entries[offset].id != id) {
        continue;
      }
      LogEntry.evictCachedData([chunk.entries[offset]]);
      final entries = writable(index)..removeAt(offset);
      if (entries.isEmpty) chunks.removeAt(index);
    }

    for (final record in delta.upsert) {
      var index = LogChunk.insertionIndex(chunks, record.id);
      if (index < chunks.length &&
          chunks[index].isPending == (record.id == pendingId)) {
        final chunk = chunks[index];
        final offset = chunk.indexOfId(record.id);
        if (offset < chunk.entries.length &&
            chunk.entries[offset].id == record.id) {
          final old = chunk.entries[offset];
          if (_sameRecord(old, record)) continue;
          LogEntry.evictCachedData([old]);
          writable(index)[offset] = _entry(record);
          continue;
        }
      } else if (record.id != pendingId &&
          index > 0 &&
          chunks[index - 1].entries.length < LogChunk.capacity) {
        index--;
      } else {
        final chunk = LogChunk(entries: [_entry(record)]);
        chunks.insert(index, chunk);
        edited.add(chunk);
        continue;
      }
      final offset = chunks[index].indexOfId(record.id);
      final entries = writable(index)..insert(offset, _entry(record));
      if (entries.length > LogChunk.capacity) {
        final split = LogChunk.capacity ~/ 2;
        final tail = LogChunk(entries: entries.sublist(split));
        entries.removeRange(split, entries.length);
        chunks.insert(index + 1, tail);
        edited.add(tail);
      }
    }
    final append = delta.pendingAppend;
    if (append != null && (chunks.isEmpty || !chunks.last.isPending)) {
      if (append.offset != 0) {
        throw StateError('Inconsistent pending log append');
      }
      final entry = LogEntry(
        Uint8List.fromList(append.data),
        LogEntryType.received,
        DateTime.fromMillisecondsSinceEpoch(append.timestampMs),
        id: pendingId,
      );
      chunks.add(LogChunk(entries: [entry]));
    } else if (append != null) {
      final index = chunks.length - 1;
      final old = chunks[index].entries.single;
      if (append.offset != old.data.length ||
          append.timestampMs != old.timestamp.millisecondsSinceEpoch) {
        throw StateError('Inconsistent pending log append');
      }
      final data = Uint8List(old.data.length + append.data.length)
        ..setRange(0, old.data.length, old.data)
        ..setRange(
          old.data.length,
          old.data.length + append.data.length,
          append.data,
        );
      final entry = LogEntry(data, old.type, old.timestamp, id: old.id);
      LogEntry.evictCachedData([old]);
      chunks[index] = LogChunk(entries: [entry]);
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
    List<UiPort>? ports,
    UiSerialConfig? appliedConfig,
    bool replaceAppliedConfig = false,
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
    appliedConfig: replaceAppliedConfig ? appliedConfig : this.appliedConfig,
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

  static UiPort _uiPort(rust.PortInfo port) => UiPort(
    portName: port.portName,
    product: port.product,
    manufacturer: port.manufacturer,
    serialNumber: port.serialNumber,
    vid: port.vid,
    pid: port.pid,
  );
  static UiSerialConfig? _serialConfig(rust.SerialConfig? config) =>
      config == null
      ? null
      : (
          portName: config.portName,
          baudRate: config.baudRate,
          dataBits: config.dataBits,
          parity: _parity(config.parity),
          stopBits: config.stopBits,
        );

  LogEntry? _existingPending() {
    final chunks = logs.chunks;
    return chunks.isNotEmpty && chunks.last.isPending
        ? chunks.last.entries.single
        : null;
  }

  static LogEntry _entry(rust.LogRecord record) => LogEntry(
    Uint8List.fromList(record.data),
    record.direction == rust.Direction.sent
        ? LogEntryType.sent
        : LogEntryType.received,
    DateTime.fromMillisecondsSinceEpoch(record.timestampMs),
    id: record.id,
  );

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
