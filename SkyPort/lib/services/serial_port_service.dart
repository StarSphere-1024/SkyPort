import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../providers/serial_provider.dart';

/// Encapsulates an opened serial port session and its reader.
class SerialPortSession {
  final SerialPort port;
  final SerialPortReader reader;
  SerialPortSession({required this.port, required this.reader});

  Stream<Uint8List> get stream => reader.stream;

  void dispose() {
    try {
      if (port.isOpen) {
        port.close();
      }
    } catch (_) {}
  }
}

/// Custom exceptions to allow precise error handling in the provider layer.
class SerialPortOpenTimeoutException implements Exception {
  final String message;
  SerialPortOpenTimeoutException([this.message = 'Serial port open timed out']);
  @override
  String toString() => 'SerialPortOpenTimeoutException: $message';
}

class SerialPortOpenException implements Exception {
  final String message;
  SerialPortOpenException([this.message = 'Failed to open serial port']);
  @override
  String toString() => 'SerialPortOpenException: $message';
}

class SerialPortWriteException implements Exception {
  final String message;
  SerialPortWriteException([this.message = 'Failed to write to serial port']);
  @override
  String toString() => 'SerialPortWriteException: $message';
}

/// Service layer responsible purely for low-level serial port operations.
/// Business/state concerns remain in Riverpod notifiers.
class SerialPortService {
  Future<SerialPortSession> open(SerialConfig config,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (config.portName.isEmpty) {
      throw SerialPortOpenException('Port name cannot be empty');
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
      final opened = await Future<bool>.value(port.openReadWrite())
          .timeout(timeout, onTimeout: () => false);
      if (!opened) {
        throw SerialPortOpenTimeoutException();
      }
      port.config = portConfig;
      final reader = SerialPortReader(port);
      success = true;
      return SerialPortSession(port: port, reader: reader);
    } on SerialPortOpenTimeoutException {
      rethrow;
    } catch (e) {
      throw SerialPortOpenException('Error opening port: $e');
    } finally {
      portConfig.dispose();
      if (!success) {
        try {
          if (port.isOpen) port.close();
        } catch (_) {}
        port.dispose();
      }
    }
  }

  Future<void> close(SerialPortSession? session) async {
    if (session == null) return;
    try {
      session.dispose();
    } catch (e) {
      // Intentionally ignore: provider decides whether to surface the error.
    }
  }

  int write(SerialPortSession session, Uint8List data, {int timeoutMs = 100}) {
    try {
      final written = session.port.write(data, timeout: timeoutMs);
      if (written <= 0) {
        throw SerialPortWriteException('No bytes written (written=$written).');
      }
      return written;
    } on SerialPortError catch (e) {
      throw SerialPortWriteException(e.message);
    } catch (e) {
      throw SerialPortWriteException('Unknown write error: $e');
    }
  }
}
