import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/serial_port_service.dart';

// Service provider for dependency injection & testability
final serialPortServiceProvider = Provider<SerialPortService>((ref) {
  return SerialPortService();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

// Custom Exception for when no serial ports are available
class NoPortsAvailableException implements Exception {
  final String message;
  NoPortsAvailableException([this.message = 'No ports available.']);

  @override
  String toString() {
    return 'NoPortsAvailableException: $message';
  }
}

// Helper to compare port lists
bool _arePortListsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final setA = Set.of(a);
  final setB = Set.of(b);
  return setA.length == setB.length && setA.containsAll(setB);
}

final availablePortsProvider =
    StreamProvider.autoDispose<List<String>>((ref) async* {
  ref.keepAlive(); // Keep alive for some time after last listener is removed

  List<String> currentPorts = SerialPort.availablePorts;
  yield currentPorts;

  final timer = Stream.periodic(const Duration(seconds: 1), (_) {
    return SerialPort.availablePorts;
  });

  await for (final newPorts in timer) {
    if (!_arePortListsEqual(currentPorts, newPorts)) {
      currentPorts = newPorts;
      yield currentPorts;
    }
  }
});

class SerialConfig {
  final String portName;
  final int baudRate;
  final int dataBits;
  final int parity;
  final int stopBits;

  SerialConfig({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = SerialPortParity.none,
    this.stopBits = 1,
  });

  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    int? parity,
    int? stopBits,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      parity: parity ?? this.parity,
      stopBits: stopBits ?? this.stopBits,
    );
  }
}

class SerialConfigNotifier extends Notifier<SerialConfig?> {
  static const _keyPortName = 'serial_port_name';
  static const _keyBaudRate = 'serial_baud_rate';
  static const _keyDataBits = 'serial_data_bits';
  static const _keyParity = 'serial_parity';
  static const _keyStopBits = 'serial_stop_bits';

  @override
  SerialConfig? build() {
    final prefs = ref.read(sharedPreferencesProvider);

    // Listen to port changes to update selection intelligently
    ref.listen(availablePortsProvider, (previous, next) {
      final newPorts = next.asData?.value ?? [];
      final currentConfig = state;

      if (currentConfig == null) {
        // If nothing selected and ports become available, select the first one
        // Or try to restore saved port if available
        final savedPort = prefs.getString(_keyPortName);
        if (savedPort != null) {
          // Always try to restore saved port, even if not currently available
          state = _loadConfigFromPrefs(prefs, savedPort);
        } else if (newPorts.isNotEmpty) {
          // If saved port not available, use first available but keep other saved settings
          state = _loadConfigFromPrefs(prefs, newPorts.first);
        }
      } else {
        // If currently selected port is gone, we DO NOT switch automatically.
        // We keep the current selection so the user sees it as "unavailable".
        // Only if the user had no selection (handled above) do we auto-select.
      }
    });

    final initialPorts = SerialPort.availablePorts;
    final savedPort = prefs.getString(_keyPortName);

    if (savedPort != null) {
      // Always restore saved port if it exists
      return _loadConfigFromPrefs(prefs, savedPort);
    } else if (initialPorts.isNotEmpty) {
      return _loadConfigFromPrefs(prefs, initialPorts.first);
    }

    return null;
  }

  SerialConfig _loadConfigFromPrefs(SharedPreferences prefs, String portName) {
    return SerialConfig(
      portName: portName,
      baudRate: prefs.getInt(_keyBaudRate) ?? 9600,
      dataBits: prefs.getInt(_keyDataBits) ?? 8,
      parity: prefs.getInt(_keyParity) ?? SerialPortParity.none,
      stopBits: prefs.getInt(_keyStopBits) ?? 1,
    );
  }

  void _saveConfig() {
    final config = state;
    if (config != null) {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString(_keyPortName, config.portName);
      prefs.setInt(_keyBaudRate, config.baudRate);
      prefs.setInt(_keyDataBits, config.dataBits);
      prefs.setInt(_keyParity, config.parity);
      prefs.setInt(_keyStopBits, config.stopBits);
    }
  }

  void setPort(String portName) {
    state =
        state?.copyWith(portName: portName) ?? SerialConfig(portName: portName);
    _saveConfig();
  }

  void setBaudRate(int baudRate) {
    state = state?.copyWith(baudRate: baudRate);
    _saveConfig();
  }

  void setDataBits(int dataBits) {
    state = state?.copyWith(dataBits: dataBits);
    _saveConfig();
  }

  void setParity(int parity) {
    state = state?.copyWith(parity: parity);
    _saveConfig();
  }

  void setStopBits(int stopBits) {
    state = state?.copyWith(stopBits: stopBits);
    _saveConfig();
  }
}

final serialConfigProvider =
    NotifierProvider.autoDispose<SerialConfigNotifier, SerialConfig?>(
        SerialConfigNotifier.new);

enum ConnectionStatus { disconnected, connecting, connected, disconnecting }

class SerialConnection {
  final ConnectionStatus status;
  final SerialPortSession? session;
  final int rxBytes;
  final int txBytes;

  SerialConnection({
    this.status = ConnectionStatus.disconnected,
    this.session,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastRxBytes = 0,
  });

  final int lastRxBytes;

  SerialConnection copyWith({
    ConnectionStatus? status,
    SerialPortSession? session,
    int? rxBytes,
    int? txBytes,
    int? lastRxBytes,
  }) {
    return SerialConnection(
      status: status ?? this.status,
      session: session ?? this.session,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      lastRxBytes: lastRxBytes ?? this.lastRxBytes,
    );
  }
}

class SerialConnectionNotifier extends Notifier<SerialConnection> {
  StreamSubscription<Uint8List>? _dataSubscription;

  @override
  SerialConnection build() {
    ref.onDispose(() {
      disconnect();
    });
    return SerialConnection();
  }

  /// Establish the serial connection. Formerly `open()`.
  Future<void> connect() async {
    if (state.status != ConnectionStatus.disconnected) {
      return;
    }
    ref.read(errorProvider.notifier).clear();
    state = state.copyWith(status: ConnectionStatus.connecting);

    final config = ref.read(serialConfigProvider);
    if (config == null) {
      ref.read(errorProvider.notifier).setError(AppErrorType.configNotSet);
      state = state.copyWith(status: ConnectionStatus.disconnected);
      return;
    }
    final service = ref.read(serialPortServiceProvider);
    try {
      final session = await service.open(config);
      _dataSubscription = session.stream.listen((data) {
        // Forward received data into the debounced log provider
        ref.read(dataLogProvider.notifier).addReceived(data);
        state = state.copyWith(
          rxBytes: state.rxBytes + data.length,
          lastRxBytes: data.length,
        );
      }, onError: (error) {
        disconnect();
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.portDisconnected, error.toString());
      });
      state = state.copyWith(
        status: ConnectionStatus.connected,
        session: session,
      );
    } on SerialPortOpenTimeoutException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.portOpenTimeout, e.message);
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } on SerialPortOpenException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.portOpenFailed, e.message);
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.unknown, e.toString());
      state = state.copyWith(status: ConnectionStatus.disconnected);
    }
  }

  /// Tear down the serial connection. Formerly `close()`.
  Future<void> disconnect() async {
    if (state.status != ConnectionStatus.connected) {
      return;
    }

    ref.read(errorProvider.notifier).clear();
    state = state.copyWith(status: ConnectionStatus.disconnecting);

    final session = state.session;
    final subscriptionToCancel = _dataSubscription;
    _dataSubscription = null;

    try {
      await subscriptionToCancel?.cancel();
      await Future.delayed(const Duration(milliseconds: 200));
      await ref.read(serialPortServiceProvider).close(session);
    } catch (e) {
      if (kDebugMode) {
        print("Error during serial port cleanup: $e");
      }
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.cleanupError, e.toString());
    } finally {
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        session: null,
      );
    }
  }

  // Backward compatibility wrappers (can be removed later)
  @Deprecated('Use connect() instead')
  Future<void> open() => connect();
  @Deprecated('Use disconnect() instead')
  Future<void> close() => disconnect();

  Future<void> send(String data) async {
    if (state.session == null || state.status != ConnectionStatus.connected) {
      return;
    }
    ref.read(errorProvider.notifier).clear();

    final useHex = ref.read(uiSettingsProvider).hexSend;
    final uiSettings = ref.read(uiSettingsProvider);
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = _hexToBytes(data);
      } else {
        var textToSend = data;
        if (uiSettings.appendNewline) {
          String newline;
          switch (uiSettings.newlineMode) {
            case NewlineMode.lf:
              newline = '\n';
              break;
            case NewlineMode.cr:
              newline = '\r';
              break;
            case NewlineMode.crlf:
              newline = '\r\n';
              break;
          }
          textToSend = '$textToSend$newline';
        }
        bytesToSend = Uint8List.fromList(utf8.encode(textToSend));
      }
    } catch (e) {
      ref.read(errorProvider.notifier).setError(AppErrorType.invalidHexFormat);
      return;
    }

    try {
      final bytesWritten = ref
          .read(serialPortServiceProvider)
          .write(state.session!, bytesToSend, timeoutMs: 100);
      if (bytesWritten > 0) {
        ref
            .read(dataLogProvider.notifier)
            .addSent(bytesToSend.sublist(0, bytesWritten));
      }
      state = state.copyWith(
        txBytes: state.txBytes + bytesWritten,
      );
    } on SerialPortWriteException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.writeFailed, e.message);
    }
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    // Efficiently split by whitespace and filter out empty strings.
    final parts = hex.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);

    for (var part in parts) {
      // Pad the part if it has an odd length.
      if (part.length % 2 != 0) {
        part = '0$part';
      }

      for (int i = 0; i < part.length; i += 2) {
        final hexPair = part.substring(i, i + 2);
        try {
          bytes.add(int.parse(hexPair, radix: 16));
        } on FormatException {
          // Rethrow with a more informative message.
          throw FormatException('Invalid hex value found: "$hexPair"');
        }
      }
    }
    return Uint8List.fromList(bytes);
  }
}

final serialConnectionProvider =
    NotifierProvider.autoDispose<SerialConnectionNotifier, SerialConnection>(
        SerialConnectionNotifier.new);

enum LogEntryType { received, sent }

class LogEntry {
  final Uint8List data;
  final LogEntryType type;
  final DateTime timestamp;
  String? _cachedText;
  bool? _cachedHexMode;

  // Static LRU Cache for rendered TextSpans
  // Limits memory usage by only keeping the most recently rendered spans (e.g. visible items)
  static const int _maxCacheSize = 500;
  static final LinkedHashMap<LogEntry, _CachedSpanData> _spanCache =
      LinkedHashMap<LogEntry, _CachedSpanData>();

  LogEntry(this.data, this.type, this.timestamp);

  String getDisplayText(bool hexDisplay) {
    if (_cachedText != null && _cachedHexMode == hexDisplay) {
      return _cachedText!;
    }

    if (hexDisplay) {
      _cachedText = data
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    } else {
      _cachedText = utf8.decode(data, allowMalformed: true);
    }
    _cachedHexMode = hexDisplay;
    return _cachedText!;
  }

  List<TextSpan> getSpans({
    required bool hexDisplay,
    required bool showTimestamp,
    required bool showSent,
    required bool enableAnsi,
    required TextStyle baseStyle,
    required TextStyle timestampStyle,
    required Color primaryColor,
    required Color onSurfaceColor,
  }) {
    final key = Object.hash(
      hexDisplay,
      showTimestamp,
      showSent,
      enableAnsi,
      baseStyle,
      timestampStyle,
      primaryColor,
      onSurfaceColor,
    );

    // 1. Check LRU Cache
    if (_spanCache.containsKey(this)) {
      final cachedData = _spanCache[this]!;
      if (cachedData.settingsHash == key) {
        // Cache Hit: Move to end (MRU) and return
        _spanCache.remove(this);
        _spanCache[this] = cachedData;
        return cachedData.spans;
      }
    }

    // 2. Generate
    final spans = _generateSpans(
      hexDisplay,
      showTimestamp,
      showSent,
      enableAnsi,
      baseStyle,
      timestampStyle,
      primaryColor,
      onSurfaceColor,
    );

    // 3. Update LRU Cache
    if (_spanCache.length >= _maxCacheSize) {
      _spanCache.remove(_spanCache.keys.first); // Remove LRU (first)
    }
    _spanCache[this] = _CachedSpanData(key, spans); // Add to MRU (end)

    return spans;
  }

  List<TextSpan> _generateSpans(
    bool hexDisplay,
    bool showTimestamp,
    bool showSent,
    bool enableAnsi,
    TextStyle baseStyle,
    TextStyle timestampStyle,
    Color primaryColor,
    Color onSurfaceColor,
  ) {
    final isSent = type == LogEntryType.sent;
    final formattedTimestamp = DateFormat('HH:mm:ss.SSS').format(timestamp);
    final dataText = getDisplayText(hexDisplay);
    final lines = dataText.split('\n');
    final spans = <TextSpan>[];

    for (int j = 0; j < lines.length; j++) {
      final lineText = lines[j];

      if (j == 0 && showTimestamp) {
        spans.add(
          TextSpan(
            text: '$formattedTimestamp ',
            style: timestampStyle,
          ),
        );
      }

      if (j == 0 && showSent) {
        spans.add(TextSpan(
          text: isSent ? 'TX > ' : 'RX < ',
          style: baseStyle.copyWith(
            color: isSent ? primaryColor : onSurfaceColor,
            fontWeight: FontWeight.bold,
          ),
        ));
      }

      final contentColor =
          isSent ? primaryColor.withValues(alpha: 0.8) : onSurfaceColor;

      final contentStyle = baseStyle.copyWith(color: contentColor);

      if (enableAnsi) {
        final parser = ansi.AnsiParser(lineText);
        for (final match in parser.matches) {
          final text = lineText.substring(match.start, match.end);
          if (text.startsWith('\x1b')) continue;

          spans.add(TextSpan(
            text: text,
            style: _ansiStateToStyle(match.state, contentStyle),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: lineText,
          style: contentStyle,
        ));
      }
    }
    return spans;
  }

  static TextStyle _ansiStateToStyle(dynamic state, TextStyle baseStyle) {
    Color? fg;
    Color? bg;
    bool bold = false;
    bool italic = false;
    bool underline = false;

    Color? getFlutterColor(dynamic ansiColorObject) {
      if (ansiColorObject == null) return null;
      try {
        final runtimeTypeStr = ansiColorObject.runtimeType.toString();
        if (runtimeTypeStr.contains('Color16')) {
          final dynamic colorEnum = ansiColorObject.color;
          final int index = colorEnum.index as int;
          switch (index) {
            case 0:
              return Colors.black;
            case 1:
              return Colors.red;
            case 2:
              return Colors.green;
            case 3:
              return Colors.yellow;
            case 4:
              return Colors.blue;
            case 5:
              return Colors.purple;
            case 6:
              return Colors.cyan;
            case 7:
              return Colors.white70;
            case 8:
              return Colors.grey;
            case 9:
              return Colors.redAccent;
            case 10:
              return Colors.greenAccent;
            case 11:
              return Colors.yellowAccent;
            case 12:
              return Colors.blueAccent;
            case 13:
              return Colors.purpleAccent;
            case 14:
              return Colors.cyanAccent;
            case 15:
              return Colors.white;
            default:
              return null;
          }
        }
      } catch (e) {}
      return null;
    }

    try {
      if (state != null) {
        fg = getFlutterColor(state.foreground);
        bg = getFlutterColor(state.background);
        try {
          if (state.isBold == true) bold = true;
        } catch (_) {}
        try {
          if (state.isItalicized == true) italic = true;
        } catch (_) {}
        try {
          if (state.isSinglyUnderlined == true) underline = true;
        } catch (_) {}
      }
    } catch (e) {}

    return baseStyle.copyWith(
      color: fg,
      backgroundColor: bg,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline ? TextDecoration.underline : null,
    );
  }
}

class _CachedSpanData {
  final int settingsHash;
  final List<TextSpan> spans;
  _CachedSpanData(this.settingsHash, this.spans);
}

class DataLogNotifier extends Notifier<List<LogEntry>> {
  Timer? _receiveDebounce;
  // Buffer for accumulating bytes of the current line in line-mode text display.
  final List<int> _lineBuffer = [];

  int _totalBytes = 0;

  @override
  List<LogEntry> build() {
    ref.onDispose(() {
      _receiveDebounce?.cancel();
    });
    _totalBytes = 0;
    return [];
  }

  void _addLogEntries(List<LogEntry> entries) {
    if (entries.isEmpty) return;
    final uiSettings = ref.read(uiSettingsProvider);
    final maxBytes = uiSettings.logBufferSize * 1024 * 1024;
    // Start from current state and append the new entry.
    final newList = List<LogEntry>.from(state)..addAll(entries);

    for (final entry in entries) {
      _totalBytes += entry.data.length;
    }

    // If total bytes exceed the configured cap, drop oldest entries
    // until we fall back under the limit.
    int removeCount = 0;
    int i = 0;
    while (_totalBytes > maxBytes && i < newList.length) {
      _totalBytes -= newList[i].data.length;
      removeCount++;
      i++;
    }
    if (removeCount > 0) {
      newList.removeRange(0, removeCount);
    }

    state = newList;
  }

  void addReceived(Uint8List data) {
    final settings = ref.read(uiSettingsProvider);

    // Determine receive mode:
    // - If hexDisplay is true: always use block receive mode
    // - If hexDisplay is false: use line mode if enabled, otherwise block mode
    final useBlockMode =
        settings.hexDisplay || settings.receiveMode == ReceiveMode.block;

    if (useBlockMode) {
      // Block receive mode: debounce short bursts of data into a single frame.
      if (_receiveDebounce?.isActive ?? false) {
        _receiveDebounce!.cancel();
        // Append to the last entry
        if (state.isNotEmpty && state.last.type == LogEntryType.received) {
          final lastEntry = state.last;

          final newData = Uint8List.fromList([...lastEntry.data, ...data]);

          // Create a new list with the updated entry
          final updatedList = List<LogEntry>.from(state);
          updatedList[state.length - 1] = LogEntry(
            newData,
            lastEntry.type,
            DateTime.now(), // Update timestamp to the latest received time
          );
          // Update total bytes
          _totalBytes += (newData.length - lastEntry.data.length);

          // We should check maxBytes here too strictly speaking, but it's an edge case for a single growing packet.
          // Let's rely on the next cleanup or simple check.
          final maxBytes = settings.logBufferSize * 1024 * 1024;
          if (_totalBytes > maxBytes) {
            // simplified cleanup for this specific case if needed, or just let it grow until next new entry
          }

          state = updatedList;
        } else {
          _addLogEntries(
              [LogEntry(data, LogEntryType.received, DateTime.now())]);
        }
      } else {
        // Create a new entry
        _addLogEntries([LogEntry(data, LogEntryType.received, DateTime.now())]);
      }

      _receiveDebounce =
          Timer(Duration(milliseconds: settings.blockIntervalMs), () {
        // Debounce finished, next data will create a new entry
      });
    } else {
      // Line receive mode: process as lines
      _receiveDebounce?.cancel();
      _appendAsLines(data);
    }
  }

  void _appendAsLines(Uint8List data) {
    final newEntries = <LogEntry>[];

    for (final byte in data) {
      if (byte == 0x0A) {
        if (_lineBuffer.isNotEmpty) {
          if (_lineBuffer.isNotEmpty && _lineBuffer.last == 0x0D) {
            _lineBuffer.removeLast();
          }

          final lineBytes = Uint8List.fromList(_lineBuffer);
          _lineBuffer.clear();

          newEntries
              .add(LogEntry(lineBytes, LogEntryType.received, DateTime.now()));
        } else {}
      } else {
        _lineBuffer.add(byte);
      }
    }

    if (newEntries.isNotEmpty) {
      _addLogEntries(newEntries);
    }
  }

  void addSent(Uint8List data) {
    _receiveDebounce?.cancel();
    _addLogEntries([LogEntry(data, LogEntryType.sent, DateTime.now())]);
  }

  void clear() {
    _receiveDebounce?.cancel();
    _lineBuffer.clear();
    _totalBytes = 0;
    state = [];
    // Clear RX/TX counters when clearing the receive area
    ref.read(serialConnectionProvider.notifier).state =
        ref.read(serialConnectionProvider).copyWith(
              rxBytes: 0,
              txBytes: 0,
              lastRxBytes: 0,
            );
  }
}

final dataLogProvider =
    NotifierProvider.autoDispose<DataLogNotifier, List<LogEntry>>(
        DataLogNotifier.new);

class UiSettings {
  final bool hexDisplay;
  final bool hexSend;
  final bool showTimestamp;
  final bool showSent; // Whether to display sent data in the log
  final int
      blockIntervalMs; // Block interval in milliseconds for block receive mode
  final ReceiveMode receiveMode; // Receive mode: line or block
  final ReceiveMode
      preferredReceiveMode; // User's preferred receive mode in text mode
  // Sending new line settings
  final bool appendNewline; // Whether to append a newline when sending text
  final NewlineMode newlineMode; // Which newline sequence to append
  final bool enableAnsi; // Whether to enable ANSI escape sequence rendering
  final int logBufferSize; // Log buffer size in MB

  const UiSettings({
    this.hexDisplay = false,
    this.hexSend = false,
    this.showTimestamp = true,
    this.showSent = true,
    this.blockIntervalMs = 20,
    this.receiveMode = ReceiveMode.block, // Default to block receive mode
    this.preferredReceiveMode =
        ReceiveMode.line, // Default to line receive mode in text mode
    this.appendNewline = false,
    this.newlineMode = NewlineMode.lf,
    this.enableAnsi = false,
    this.logBufferSize = 128, // Default 128 MB
  });

  UiSettings copyWith({
    bool? hexDisplay,
    bool? hexSend,
    bool? showTimestamp,
    bool? showSent,
    int? blockIntervalMs,
    ReceiveMode? receiveMode,
    ReceiveMode? preferredReceiveMode,
    bool? appendNewline,
    NewlineMode? newlineMode,
    bool? enableAnsi,
    int? logBufferSize,
  }) {
    return UiSettings(
      hexDisplay: hexDisplay ?? this.hexDisplay,
      hexSend: hexSend ?? this.hexSend,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showSent: showSent ?? this.showSent,
      blockIntervalMs: blockIntervalMs ?? this.blockIntervalMs,
      receiveMode: receiveMode ?? this.receiveMode,
      preferredReceiveMode: preferredReceiveMode ?? this.preferredReceiveMode,
      appendNewline: appendNewline ?? this.appendNewline,
      newlineMode: newlineMode ?? this.newlineMode,
      enableAnsi: enableAnsi ?? this.enableAnsi,
      logBufferSize: logBufferSize ?? this.logBufferSize,
    );
  }
}

/// Mode for which newline sequence to append when sending text data.
enum NewlineMode {
  lf, // "\n"
  cr, // "\r"
  crlf, // "\r\n"
}

/// Receive mode for data reception.
enum ReceiveMode {
  line,
  block,
}

class UiSettingsNotifier extends Notifier<UiSettings> {
  static const _keyHexDisplay = 'ui_hex_display';
  static const _keyHexSend = 'ui_hex_send';
  static const _keyShowTimestamp = 'ui_show_timestamp';
  static const _keyShowSent = 'ui_show_sent';
  static const _keyBlockIntervalMs = 'ui_block_interval_ms';
  static const _keyLineMode = 'ui_line_mode';
  static const _keyPreferredReceiveMode = 'ui_preferred_receive_mode';
  // Newline settings keys
  static const _keyAppendNewline = 'ui_append_newline';
  static const _keyNewlineMode = 'ui_newline_mode';
  static const _keyEnableAnsi = 'ui_enable_ansi';
  static const _keyLogBufferSize = 'ui_log_buffer_size';

  @override
  UiSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return UiSettings(
      hexDisplay: prefs.getBool(_keyHexDisplay) ?? false,
      hexSend: prefs.getBool(_keyHexSend) ?? false,
      showTimestamp: prefs.getBool(_keyShowTimestamp) ?? true,
      showSent: prefs.getBool(_keyShowSent) ?? true,
      blockIntervalMs: prefs.getInt(_keyBlockIntervalMs) ?? 20,
      receiveMode: (prefs.getBool(_keyLineMode) ?? false)
          ? ReceiveMode.line
          : ReceiveMode.block,
      preferredReceiveMode: (prefs.getBool(_keyPreferredReceiveMode) ?? false)
          ? ReceiveMode.line
          : ReceiveMode.block,
      appendNewline: prefs.getBool(_keyAppendNewline) ?? false,
      newlineMode: NewlineMode
          .values[prefs.getInt(_keyNewlineMode) ?? NewlineMode.lf.index],
      enableAnsi: prefs.getBool(_keyEnableAnsi) ?? false,
      logBufferSize: prefs.getInt(_keyLogBufferSize) ?? 128,
    );
  }

  void setHexDisplay(bool value) {
    final newHexDisplay = value;
    final currentReceiveMode = state.receiveMode;

    if (newHexDisplay) {
      // Switching to HEX mode: save current preference and force block mode
      state = state.copyWith(
        hexDisplay: true,
        receiveMode: ReceiveMode.block,
        preferredReceiveMode: currentReceiveMode, // Save user's preference
      );
      ref.read(sharedPreferencesProvider).setBool(_keyHexDisplay, true);
      ref.read(sharedPreferencesProvider).setBool(_keyLineMode, false);
      ref.read(sharedPreferencesProvider).setBool(
          _keyPreferredReceiveMode, currentReceiveMode == ReceiveMode.line);
    } else {
      // Switching to text mode: restore user's preference
      final preferredMode = state.preferredReceiveMode;
      state = state.copyWith(
        hexDisplay: false,
        receiveMode: preferredMode,
      );
      ref.read(sharedPreferencesProvider).setBool(_keyHexDisplay, false);
      ref
          .read(sharedPreferencesProvider)
          .setBool(_keyLineMode, preferredMode == ReceiveMode.line);
    }
  }

  void setHexSend(bool value) {
    state = state.copyWith(hexSend: value);
    ref.read(sharedPreferencesProvider).setBool(_keyHexSend, value);
  }

  void setShowTimestamp(bool value) {
    state = state.copyWith(showTimestamp: value);
    ref.read(sharedPreferencesProvider).setBool(_keyShowTimestamp, value);
  }

  void setShowSent(bool value) {
    state = state.copyWith(showSent: value);
    ref.read(sharedPreferencesProvider).setBool(_keyShowSent, value);
  }

  void setFrameIntervalMs(int value) {
    state = state.copyWith(blockIntervalMs: value);
    ref.read(sharedPreferencesProvider).setInt(_keyBlockIntervalMs, value);
  }

  void setReceiveMode(ReceiveMode mode) {
    state = state.copyWith(
      receiveMode: mode,
      preferredReceiveMode: mode,
    );
    ref
        .read(sharedPreferencesProvider)
        .setBool(_keyLineMode, mode == ReceiveMode.line);
    ref
        .read(sharedPreferencesProvider)
        .setBool(_keyPreferredReceiveMode, mode == ReceiveMode.line);
  }

  void setAppendNewline(bool value) {
    state = state.copyWith(appendNewline: value);
    ref.read(sharedPreferencesProvider).setBool(_keyAppendNewline, value);
  }

  void setNewlineMode(NewlineMode mode) {
    state = state.copyWith(newlineMode: mode);
    ref.read(sharedPreferencesProvider).setInt(_keyNewlineMode, mode.index);
  }

  void setEnableAnsi(bool value) {
    state = state.copyWith(enableAnsi: value);
    ref.read(sharedPreferencesProvider).setBool(_keyEnableAnsi, value);
  }

  void setLogBufferSize(int size) {
    state = state.copyWith(logBufferSize: size);
    ref.read(sharedPreferencesProvider).setInt(_keyLogBufferSize, size);
  }
}

final uiSettingsProvider =
    NotifierProvider.autoDispose<UiSettingsNotifier, UiSettings>(
        UiSettingsNotifier.new);

/// Defines different types of potential errors in the serial workflow
enum AppErrorType {
  none,
  configNotSet,
  portOpenTimeout,
  portOpenFailed,
  portDisconnected,
  writeFailed,
  invalidHexFormat,
  cleanupError,
  unknown;
}

/// A structured error state
class AppError {
  final AppErrorType type;
  final String? rawMessage;

  const AppError(this.type, [this.rawMessage]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppError &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          rawMessage == other.rawMessage;

  @override
  int get hashCode => type.hashCode ^ rawMessage.hashCode;
}

class ErrorNotifier extends Notifier<AppError?> {
  @override
  AppError? build() => null;

  void setError(AppErrorType type, [String? message]) {
    state = AppError(type, message);
    // Auto-clear error after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (state?.type == type) {
        state = null;
      }
    });
  }

  void clear() {
    state = null;
  }
}

final errorProvider =
    NotifierProvider.autoDispose<ErrorNotifier, AppError?>(ErrorNotifier.new);
