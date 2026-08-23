import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/serial_config.dart';
import 'app_logger.dart';
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
  int write(Uint8List data,
      {int timeoutMs = SkyPortConstants.defaultWriteTimeoutMs});

  /// Close the serial port and release resources.
  Future<void> dispose();
}

/// Production implementation of SerialPortSessionInterface.
///
/// Encapsulates an opened serial port session and its lifecycle.
/// This class contains FFI dependencies and should only be used
/// in production code, not in tests.
class SerialPortSession implements SerialPortSessionInterface {
  final SerialPort _port;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  Timer? _pollTimer;
  Future<void>? _disposeFuture;
  _SerialPortSessionState _state = _SerialPortSessionState.active;
  bool _pollingFailed = false;

  SerialPortSession({required SerialPort port}) : _port = port {
    _controller
      ..onListen = _startPolling
      ..onCancel = _stopPolling;
  }

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  int write(Uint8List data,
      {int timeoutMs = SkyPortConstants.defaultWriteTimeoutMs}) {
    if (_state != _SerialPortSessionState.active || _pollingFailed) {
      throw SerialPortWriteException('Serial port session is disposed');
    }
    try {
      final written = _port.write(data, timeout: timeoutMs);
      if (written <= 0) {
        throw SerialPortWriteException('No bytes written (written=$written).');
      }
      return written;
    } on SerialPortError catch (e, stackTrace) {
      AppLogger.instance.error(
        'Serial port write failed',
        name: 'skyport.serial',
        error: e,
        stackTrace: stackTrace,
      );
      throw SerialPortWriteException(e.message);
    } catch (e, stackTrace) {
      AppLogger.instance.error(
        'Serial port write failed',
        name: 'skyport.serial',
        error: e,
        stackTrace: stackTrace,
      );
      throw SerialPortWriteException('Unknown write error: $e');
    }
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _state = _SerialPortSessionState.disposing;
    _stopPolling();
    return _disposeFuture = _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    try {
      await _controller.close();
    } finally {
      try {
        if (_port.isOpen) {
          _port.close();
        }
      } catch (e, stackTrace) {
        AppLogger.instance.warning(
          'Failed to close serial port',
          name: 'skyport.serial',
          error: e,
          stackTrace: stackTrace,
        );
      }
      try {
        _port.dispose();
      } catch (e, stackTrace) {
        AppLogger.instance.warning(
          'Failed to dispose serial port',
          name: 'skyport.serial',
          error: e,
          stackTrace: stackTrace,
        );
      }
      _state = _SerialPortSessionState.disposed;
    }
  }

  void _startPolling() {
    if (_state != _SerialPortSessionState.active ||
        _pollingFailed ||
        _pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: SkyPortConstants.serialReadPollTimeoutMs),
      (_) => _poll(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _poll() {
    if (_state != _SerialPortSessionState.active || _pollingFailed) return;
    try {
      final available = _port.bytesAvailable;
      if (available <= 0) return;
      final data = _port.read(available, timeout: 0);
      if (data.isNotEmpty) _controller.add(data);
    } catch (e, stackTrace) {
      _pollingFailed = true;
      _stopPolling();
      _controller.addError(e, stackTrace);
    }
  }
}

enum _SerialPortSessionState { active, disposing, disposed }

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
  Future<SerialPortSessionInterface> open(SerialConfig config);

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
  Future<SerialPortSessionInterface> open(SerialConfig config) async {
    if (config.portName.isEmpty) {
      final error = SerialPortOpenException('Port name cannot be empty');
      AppLogger.instance.error(
        'Serial port open failed',
        name: 'skyport.serial',
        error: error,
        stackTrace: StackTrace.current,
      );
      throw error;
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
      final opened = port.openReadWrite();
      if (!opened) {
        throw SerialPortOpenException('Failed to open port');
      }
      port.config = portConfig;
      success = true;
      return SerialPortSession(port: port);
    } on SerialPortOpenException catch (e, stackTrace) {
      AppLogger.instance.error(
        'Serial port open failed',
        name: 'skyport.serial',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.instance.error(
        'Serial port open failed',
        name: 'skyport.serial',
        error: e,
        stackTrace: stackTrace,
      );
      throw SerialPortOpenException('Error opening port: $e');
    } finally {
      try {
        portConfig.dispose();
      } catch (e, stackTrace) {
        AppLogger.instance.warning(
          'Failed to dispose serial port configuration',
          name: 'skyport.serial',
          error: e,
          stackTrace: stackTrace,
        );
        rethrow;
      }
      if (!success) {
        try {
          if (port.isOpen) port.close();
        } catch (e, stackTrace) {
          AppLogger.instance.warning(
            'Failed to close serial port after open failure',
            name: 'skyport.serial',
            error: e,
            stackTrace: stackTrace,
          );
        }
        try {
          port.dispose();
        } catch (e, stackTrace) {
          AppLogger.instance.warning(
            'Failed to dispose serial port after open failure',
            name: 'skyport.serial',
            error: e,
            stackTrace: stackTrace,
          );
          rethrow;
        }
      }
    }
  }

  @override
  Future<void> close(SerialPortSessionInterface? session) async {
    if (session == null) return;
    try {
      await session.dispose();
    } catch (e, stackTrace) {
      AppLogger.instance.warning(
        'Failed to close serial port session',
        name: 'skyport.serial',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
