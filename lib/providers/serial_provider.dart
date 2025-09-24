import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Provider for available serial ports
final availablePortsProvider = FutureProvider<List<String>>((ref) async {
  return SerialPort.availablePorts;
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
    if (availablePorts.isNotEmpty) {
      state = SerialConfig(portName: availablePorts.first);
    }
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
    StateNotifierProvider<SerialConfigNotifier, SerialConfig?>((ref) {
  final availablePorts = ref.watch(availablePortsProvider).value ?? [];
  return SerialConfigNotifier(availablePorts);
});

// 4. Provider for serial connection management
enum ConnectionStatus { disconnected, connected }

class SerialConnection {
  final ConnectionStatus status;
  final SerialPort? port;
  final SerialPortReader? reader;
  final int rxBytes;
  final int txBytes;
  final String? errorMessage;

  SerialConnection({
    this.status = ConnectionStatus.disconnected,
    this.port,
    this.reader,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.errorMessage,
  });

  SerialConnection copyWith({
    ConnectionStatus? status,
    SerialPort? port,
    SerialPortReader? reader,
    int? rxBytes,
    int? txBytes,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SerialConnection(
      status: status ?? this.status,
      port: port ?? this.port,
      reader: reader ?? this.reader,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SerialConnectionNotifier extends StateNotifier<SerialConnection> {
  final Ref _ref;
  StreamSubscription<Uint8List>? _dataSubscription;

  SerialConnectionNotifier(this._ref) : super(SerialConnection());

  Future<void> open() async {
    final config = _ref.read(serialConfigProvider);
    if (config == null) {
      state = state.copyWith(errorMessage: 'Serial configuration not set.');
      return;
    }

    final port = SerialPort(config.portName);
    try {
      final opened = port.openReadWrite();
      if (!opened) {
        final error = SerialPort.lastError;
        throw SerialPortError('Failed to open port: ${error?.message}');
      }

      // Apply configuration
      final newConfig = SerialPortConfig();
      newConfig.baudRate = config.baudRate;
      newConfig.bits = config.dataBits;
      newConfig.parity = config.parity;
      newConfig.stopBits = config.stopBits;
      port.config = newConfig;

      final reader = SerialPortReader(port);
      _dataSubscription = reader.stream.listen((data) {
        _ref.read(dataLogProvider.notifier).addReceived(data);
        state = state.copyWith(rxBytes: state.rxBytes + data.length);
      });

      state = state.copyWith(
        status: ConnectionStatus.connected,
        port: port,
        reader: reader,
        clearError: true,
      );
    } on SerialPortError catch (e) {
      state = state.copyWith(errorMessage: 'Error: ${e.message}');
    }
  }

  Future<void> close() async {
    await _dataSubscription?.cancel();
    state.port?.close();
    state = SerialConnection(); // Reset to initial state
  }

  Future<void> send(String data) async {
    if (state.port == null) return;

    final useHex = _ref.read(settingsProvider).hexSend;
    Uint8List bytesToSend;

    if (useHex) {
      try {
        bytesToSend = _hexToBytes(data);
      } catch (e) {
        state = state.copyWith(errorMessage: 'Invalid Hex format.');
        return;
      }
    } else {
      bytesToSend = Uint8List.fromList(utf8.encode(data));
    }

    try {
      final bytesWritten = state.port!.write(bytesToSend);
      _ref.read(dataLogProvider.notifier).addSent(bytesToSend);
      state = state.copyWith(txBytes: state.txBytes + bytesWritten);
    } on SerialPortError catch (e) {
      state = state.copyWith(errorMessage: 'Error sending data: ${e.message}');
    }
  }

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}

final serialConnectionProvider =
    StateNotifierProvider<SerialConnectionNotifier, SerialConnection>((ref) {
  return SerialConnectionNotifier(ref);
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
    StateNotifierProvider<DataLogNotifier, List<LogEntry>>((ref) {
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
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
