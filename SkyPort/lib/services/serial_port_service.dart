import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/serial_config.dart';
import '../utils/constants.dart';

/// Abstract interface for a serial port session to enable mocking.
///
/// This interface encapsulates both read and write operations for an
/// active serial port connection, hiding FFI implementation details.
abstract class SerialPortSessionInterface {
  /// Stream of incoming data from the serial port.
  Stream<Uint8List> get stream;

  /// Write data to the serial port.
  /// Returns the number of bytes written.
  /// Throws [SerialPortWriteException] on failure.
  int write(Uint8List data, {int timeoutMs = SkyPortConstants.defaultWriteTimeoutMs});

  /// Close the serial port and release resources.
  void dispose();
}

/// Production implementation of SerialPortSessionInterface.
///
/// Encapsulates an opened serial port session and its reader.
/// This class contains FFI dependencies and should only be used
/// in production code, not in tests.
class SerialPortSession implements SerialPortSessionInterface {
  final SerialPort _port;
  final SerialPortReader _reader;

  SerialPortSession({required SerialPort port, required SerialPortReader reader})
      : _port = port,
        _reader = reader;

  @override
  Stream<Uint8List> get stream => _reader.stream;

  @override
  int write(Uint8List data, {int timeoutMs = SkyPortConstants.defaultWriteTimeoutMs}) {
    try {
      final written = _port.write(data, timeout: timeoutMs);
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

  @override
  void dispose() {
    try {
      if (_port.isOpen) {
        _port.close();
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

/// Abstract interface for serial port operations to enable mocking.
abstract class SerialPortServiceInterface {
  /// Get list of available serial ports.
  Future<List<String>> getAvailablePorts();

  /// Open a serial port session.
  Future<SerialPortSessionInterface> open(SerialConfig config,
      {Duration timeout = const Duration(seconds: 5)});

  /// Close a serial port session.
  Future<void> close(SerialPortSessionInterface? session);
}

/// Service layer responsible purely for low-level serial port operations.
/// Business/state concerns remain in Riverpod notifiers.
class SerialPortService implements SerialPortServiceInterface {
  @override
  Future<List<String>> getAvailablePorts() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<SerialPortSessionInterface> open(SerialConfig config,
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

  @override
  Future<void> close(SerialPortSessionInterface? session) async {
    if (session == null) return;
    try {
      session.dispose();
    } catch (e) {
      // Intentionally ignore: provider decides whether to surface the error.
    }
  }
}
