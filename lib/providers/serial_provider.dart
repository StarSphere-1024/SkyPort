import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/serial_port_service.dart';

// Service provider for dependency injection & testability
final serialPortServiceProvider = Provider<SerialPortService>((ref) {
  return SerialPortService();
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

// 1. Provider for available serial ports
final availablePortsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  ref.keepAlive(); // Keep alive for some time after last listener is removed
  final ports = SerialPort.availablePorts;
  ref.onDispose(() {
    // No specific cleanup needed for availablePorts, but good practice
  });
  return ports;
});

// 2. Model for serial port configuration
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

// 3. Provider for serial port configuration state
class SerialConfigNotifier extends Notifier<SerialConfig?> {
  @override
  SerialConfig? build() {
    final availablePorts = ref.watch(availablePortsProvider).value ?? [];
    if (availablePorts.isNotEmpty) {
      return SerialConfig(portName: availablePorts.first);
    }
    return null;
  }

  void setPort(String portName) {
    state =
        state?.copyWith(portName: portName) ?? SerialConfig(portName: portName);
  }

  void setBaudRate(int baudRate) {
    state = state?.copyWith(baudRate: baudRate);
  }

  void setDataBits(int dataBits) {
    state = state?.copyWith(dataBits: dataBits);
  }

  void setParity(int parity) {
    state = state?.copyWith(parity: parity);
  }

  void setStopBits(int stopBits) {
    state = state?.copyWith(stopBits: stopBits);
  }
}

final serialConfigProvider =
    NotifierProvider.autoDispose<SerialConfigNotifier, SerialConfig?>(
        SerialConfigNotifier.new);

// 4. Provider for serial connection management
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
  });

  SerialConnection copyWith({
    ConnectionStatus? status,
    SerialPortSession? session,
    int? rxBytes,
    int? txBytes,
  }) {
    return SerialConnection(
      status: status ?? this.status,
      session: session ?? this.session,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
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
      ref
          .read(errorProvider.notifier)
          .setError('Serial configuration not set.');
      state = state.copyWith(status: ConnectionStatus.disconnected);
      return;
    }
    final service = ref.read(serialPortServiceProvider);
    try {
      final session = await service.open(config);
      _dataSubscription = session.stream.listen((data) {
        // Forward received data into the debounced log provider
        ref.read(dataLogProvider.notifier).addReceived(data);
        state = state.copyWith(rxBytes: state.rxBytes + data.length);
      }, onError: (error) {
        disconnect();
        ref.read(errorProvider.notifier).setError("Port disconnected: $error");
      });
      state = state.copyWith(
        status: ConnectionStatus.connected,
        session: session,
      );
    } on SerialPortOpenTimeoutException catch (e) {
      ref.read(errorProvider.notifier).setError('Error: ${e.message}');
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } on SerialPortOpenException catch (e) {
      ref.read(errorProvider.notifier).setError(e.message);
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } catch (e) {
      ref.read(errorProvider.notifier).setError('Unknown connect error: $e');
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
      ref.read(errorProvider.notifier).setError('Error disconnecting port: $e');
    } finally {
      state = SerialConnection();
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
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = _hexToBytes(data);
      } else {
        bytesToSend = Uint8List.fromList(utf8.encode(data));
      }
    } catch (e) {
      ref.read(errorProvider.notifier).setError('Invalid Hex format.');
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
          .setError('Error sending data: ${e.message}');
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

// 5. Data Log Provider
enum LogEntryType { received, sent }

class LogEntry {
  Uint8List data;
  final LogEntryType type;
  DateTime timestamp;

  LogEntry(this.data, this.type, this.timestamp);
}

class DataLogNotifier extends Notifier<List<LogEntry>> {
  Timer? _receiveDebounce;
  static const _debounceDuration = Duration(milliseconds: 50);

  @override
  List<LogEntry> build() {
    ref.onDispose(() {
      _receiveDebounce?.cancel();
    });
    return [];
  }

  void addReceived(Uint8List data) {
    if (_receiveDebounce?.isActive ?? false) {
      _receiveDebounce!.cancel();
      // Append to the last entry
      if (state.isNotEmpty && state.last.type == LogEntryType.received) {
        final lastEntry = state.last;
        // Create a new list with the updated entry
        final updatedList = List<LogEntry>.from(state);
        updatedList[state.length - 1] = LogEntry(
          Uint8List.fromList([...lastEntry.data, ...data]),
          lastEntry.type,
          DateTime.now(), // Update timestamp to the latest received time
        );
        state = updatedList;
      } else {
        // This case should be rare, but handle it by creating a new entry
        state = [
          ...state,
          LogEntry(data, LogEntryType.received, DateTime.now())
        ];
      }
    } else {
      // Create a new entry
      state = [...state, LogEntry(data, LogEntryType.received, DateTime.now())];
    }

    _receiveDebounce = Timer(_debounceDuration, () {
      // Debounce finished, next data will create a new entry
    });
  }

  void addSent(Uint8List data) {
    // Sent data should always create a new entry and not be debounced
    _receiveDebounce?.cancel(); // Cancel any pending receive debounce
    state = [...state, LogEntry(data, LogEntryType.sent, DateTime.now())];
  }

  void clear() {
    _receiveDebounce?.cancel();
    state = [];
  }
}

final dataLogProvider =
    NotifierProvider.autoDispose<DataLogNotifier, List<LogEntry>>(
        DataLogNotifier.new);

class UiSettings {
  final bool hexDisplay;
  final bool hexSend;

  const UiSettings({this.hexDisplay = false, this.hexSend = false});

  UiSettings copyWith({bool? hexDisplay, bool? hexSend}) {
    return UiSettings(
      hexDisplay: hexDisplay ?? this.hexDisplay,
      hexSend: hexSend ?? this.hexSend,
    );
  }
}

class UiSettingsNotifier extends Notifier<UiSettings> {
  @override
  UiSettings build() => const UiSettings();

  void setHexDisplay(bool value) {
    state = state.copyWith(hexDisplay: value);
  }

  void setHexSend(bool value) {
    state = state.copyWith(hexSend: value);
  }
}

final uiSettingsProvider =
    NotifierProvider.autoDispose<UiSettingsNotifier, UiSettings>(
        UiSettingsNotifier.new);

// 7. Global Error Provider
class ErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String message) {
    state = message;
  }

  void clear() {
    state = null;
  }
}

final errorProvider =
    NotifierProvider.autoDispose<ErrorNotifier, String?>(ErrorNotifier.new);
