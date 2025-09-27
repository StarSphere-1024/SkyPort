import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class SerialConfigNotifier extends StateNotifier<SerialConfig?> {
  SerialConfigNotifier(List<String> availablePorts) : super(null) {
    if (availablePorts.isEmpty) {
      throw NoPortsAvailableException('No ports available');
    }
    state = SerialConfig(portName: availablePorts.first);
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
    StateNotifierProvider.autoDispose<SerialConfigNotifier, SerialConfig?>(
        (ref) {
  final availablePorts = ref.watch(availablePortsProvider).value ?? [];
  return SerialConfigNotifier(availablePorts);
});

// 4. Provider for serial connection management
enum ConnectionStatus { disconnected, connecting, connected, disconnecting }

class SerialConnection {
  final ConnectionStatus status;
  final SerialPort? port;
  final SerialPortReader? reader;
  final int rxBytes;
  final int txBytes;

  SerialConnection({
    this.status = ConnectionStatus.disconnected,
    this.port,
    this.reader,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  SerialConnection copyWith({
    ConnectionStatus? status,
    SerialPort? port,
    SerialPortReader? reader,
    int? rxBytes,
    int? txBytes,
  }) {
    return SerialConnection(
      status: status ?? this.status,
      port: port ?? this.port,
      reader: reader ?? this.reader,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
    );
  }
}

class SerialConnectionNotifier extends StateNotifier<SerialConnection> {
  final Ref _ref;
  StreamSubscription<Uint8List>? _dataSubscription;

  SerialConnectionNotifier(this._ref) : super(SerialConnection());

  @override
  void dispose() {
    state.port?.close();
    state.port?.dispose();
    super.dispose();
  }

  Future<void> open() async {
    if (state.status != ConnectionStatus.disconnected) {
      return;
    }
    _ref.read(errorProvider.notifier).clear();
    state = state.copyWith(status: ConnectionStatus.connecting);

    final config = _ref.read(serialConfigProvider);
    if (config == null) {
      _ref
          .read(errorProvider.notifier)
          .setError('Serial configuration not set.');
      state = state.copyWith(status: ConnectionStatus.disconnected);
      return;
    }

    final port = SerialPort(config.portName);
    final portConfig = SerialPortConfig()
      ..baudRate = config.baudRate
      ..bits = config.dataBits
      ..parity = config.parity
      ..stopBits = config.stopBits
      ..xonXoff = SerialPortXonXoff.disabled
      ..rts = SerialPortRts.off
      ..cts = SerialPortCts.ignore
      ..dsr = SerialPortDsr.ignore
      ..dtr = SerialPortDtr.off;

    bool success = false;
    try {
      if (!await Future.value(port.openReadWrite())
          .timeout(const Duration(seconds: 5))) {
        throw SerialPortError(
            'Failed to open port: ${SerialPort.lastError?.message ?? "Unknown error"}');
      }

      port.config = portConfig;

      final reader = SerialPortReader(port);
      _dataSubscription = reader.stream.listen((data) {
        if (!mounted) return;
        _ref.read(dataLogProvider.notifier).addReceived(data);
        state = state.copyWith(rxBytes: state.rxBytes + data.length);
      }, onError: (error) {
        if (!mounted) return;
        close();
        _ref.read(errorProvider.notifier).setError("Port disconnected: $error");
      });

      success = true;
      state = state.copyWith(
        status: ConnectionStatus.connected,
        port: port,
        reader: reader,
      );
    } on TimeoutException {
      _ref
          .read(errorProvider.notifier)
          .setError('Error: Port opening timed out.');
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } catch (e) {
      _ref.read(errorProvider.notifier).setError('Error: $e');
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } finally {
      portConfig.dispose();
      if (!success) {
        if (port.isOpen) {
          port.close();
        }
        port.dispose();
      }
    }
  }

  Future<void> close() async {
    if (state.status != ConnectionStatus.connected) {
      return;
    }

    state = state.copyWith(status: ConnectionStatus.disconnecting);

    final portToDispose = state.port;
    final readerToClose = state.reader;
    final subscriptionToCancel = _dataSubscription;
    _dataSubscription = null;

    try {
      await subscriptionToCancel?.cancel();
      await Future.delayed(const Duration(milliseconds: 200));
      portToDispose?.close();
    } catch (e) {
      if (kDebugMode) {
        print("Error during serial port cleanup: $e");
      }
    } finally {
      readerToClose?.close();
      portToDispose?.dispose();
      if (mounted) {
        state = SerialConnection();
      }
    }
  }

  Future<void> send(String data) async {
    if (state.port == null || state.status != ConnectionStatus.connected) {
      return;
    }
    _ref.read(errorProvider.notifier).clear();

    final useHex = _ref.read(settingsProvider).hexSend;
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = _hexToBytes(data);
      } else {
        bytesToSend = Uint8List.fromList(utf8.encode(data));
      }
    } catch (e) {
      _ref.read(errorProvider.notifier).setError('Invalid Hex format.');
      return;
    }

    try {
      final bytesWritten = state.port!.write(bytesToSend, timeout: 100);
      if (bytesWritten > 0) {
        _ref
            .read(dataLogProvider.notifier)
            .addSent(bytesToSend.sublist(0, bytesWritten));
      }
      state = state.copyWith(
        txBytes: state.txBytes + bytesWritten,
      );
    } on SerialPortError catch (e) {
      _ref
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

final serialConnectionProvider = StateNotifierProvider.autoDispose<
    SerialConnectionNotifier, SerialConnection>((ref) {
  final notifier = SerialConnectionNotifier(ref);
  ref.onDispose(() {
    notifier.close(); // Ensure connection is closed when provider is disposed
  });
  return notifier;
});

// 5. Data Log Provider
enum LogEntryType { received, sent }

class LogEntry {
  final Uint8List data;
  final LogEntryType type;
  final DateTime timestamp;

  LogEntry(this.data, this.type) : timestamp = DateTime.now();
}

class DataLogNotifier extends StateNotifier<List<LogEntry>> {
  DataLogNotifier() : super([]);

  void addReceived(Uint8List data) {
    state = [...state, LogEntry(data, LogEntryType.received)];
  }

  void addSent(Uint8List data) {
    state = [...state, LogEntry(data, LogEntryType.sent)];
  }

  void clear() {
    state = [];
  }
}

final dataLogProvider =
    StateNotifierProvider.autoDispose<DataLogNotifier, List<LogEntry>>((ref) {
  return DataLogNotifier();
});

// 6. Settings provider
class AppSettings {
  final bool hexDisplay;
  final bool hexSend;

  AppSettings({this.hexDisplay = false, this.hexSend = false});

  AppSettings copyWith({bool? hexDisplay, bool? hexSend}) {
    return AppSettings(
      hexDisplay: hexDisplay ?? this.hexDisplay,
      hexSend: hexSend ?? this.hexSend,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings());

  void setHexDisplay(bool value) {
    state = state.copyWith(hexDisplay: value);
  }

  void setHexSend(bool value) {
    state = state.copyWith(hexSend: value);
  }
}

final settingsProvider =
    StateNotifierProvider.autoDispose<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

// 7. Global Error Provider
class ErrorNotifier extends StateNotifier<String?> {
  ErrorNotifier() : super(null);

  void setError(String message) {
    state = message;
  }

  void clear() {
    state = null;
  }
}

final errorProvider =
    StateNotifierProvider.autoDispose<ErrorNotifier, String?>((ref) {
  return ErrorNotifier();
});
