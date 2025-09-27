import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
enum ConnectionStatus { disconnected, connecting, connected, disconnecting }

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

    state =
        state.copyWith(status: ConnectionStatus.connecting, clearError: true);

    final config = _ref.read(serialConfigProvider);
    if (config == null) {
      state = SerialConnection(errorMessage: 'Serial configuration not set.');
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
      if (!port.openReadWrite()) {
        throw SerialPortError(
            'Failed to open port: ${SerialPort.lastError?.message ?? "Unknown error"}');
      }

      port.config = portConfig;

      final reader = SerialPortReader(port);
      _dataSubscription = reader.stream.listen((data) {
        if (mounted) {
          _ref.read(dataLogProvider.notifier).addReceived(data);
          state = state.copyWith(rxBytes: state.rxBytes + data.length);
        }
      }, onError: (error) {
        if (mounted) {
          close();
          state = state.copyWith(errorMessage: "Port disconnected: $error");
        }
      });

      success = true;
      state = state.copyWith(
        status: ConnectionStatus.connected,
        port: port,
        reader: reader,
      );
    } catch (e) {
      state = SerialConnection(errorMessage: 'Error: $e');
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
    final subscriptionToCancel = _dataSubscription;
    _dataSubscription = null;

    try {
      await subscriptionToCancel?.cancel();

      await Future.delayed(const Duration(milliseconds: 200));

      portToDispose?.close();
      portToDispose?.dispose();
    } catch (e) {
      if (kDebugMode) {
        print("Error during serial port cleanup: $e");
      }
    } finally {
      if (mounted) {
        state = SerialConnection();
      }
    }
  }

  Future<void> send(String data) async {
    if (state.port == null || state.status != ConnectionStatus.connected) {
      return;
    }

    final useHex = _ref.read(settingsProvider).hexSend;
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = _hexToBytes(data);
      } else {
        bytesToSend = Uint8List.fromList(utf8.encode(data));
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Invalid Hex format.');
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
        clearError: true,
      );
    } on SerialPortError catch (e) {
      state = state.copyWith(errorMessage: 'Error sending data: ${e.message}');
    }
  }

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (hex.isEmpty) return Uint8List(0);
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
