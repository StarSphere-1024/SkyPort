import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/services/serial_port_service.dart';
import 'package:skyport/models/serial_config.dart';

/// Mock implementation of SerialPortServiceInterface for testing
class MockSerialPortService extends Mock
    implements SerialPortServiceInterface {}

/// Fake implementation of SerialPortServiceInterface for testing
class FakeSerialPortService implements SerialPortServiceInterface {
  final List<String> _availablePorts;

  FakeSerialPortService({List<String>? availablePorts})
      : _availablePorts = availablePorts ?? ['COM1', 'COM2'];

  @override
  Future<List<String>> getAvailablePorts() async => _availablePorts;

  @override
  Future<SerialPortSessionInterface> open(SerialConfig config,
      {Duration timeout = const Duration(seconds: 5)}) async {
    // Return a FakeSerialPortSession
    return FakeSerialPortSession();
  }

  @override
  Future<void> close(SerialPortSessionInterface? session) async {
    // Simulate closing
    session?.dispose();
  }
}

/// Fake implementation of SerialPortSessionInterface for testing
///
/// This is a PURE Dart mock with NO FFI dependencies.
/// It uses StreamController to simulate incoming data streams,
/// allowing tests to run without real hardware or FFI bindings.
class FakeSerialPortSession implements SerialPortSessionInterface {
  final StreamController<Uint8List> _controller =
      StreamController.broadcast();

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  int write(Uint8List data, {int timeoutMs = 100}) {
    // Simulate successful write
    return data.length;
  }

  /// Simulates incoming data from the serial port
  void simulateIncomingData(Uint8List data) {
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  /// Simulates an error in the data stream
  void simulateError(Object error, [StackTrace? stackTrace]) {
    if (!_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
  }

  @override
  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

/// Mock implementation of SharedPreferences for testing
///
/// This in-memory mock allows testing settings persistence
/// without requiring actual platform storage.
class FakeSharedPreferences implements SharedPreferences {
  final Map<String, Object?> _data = {};

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  List<String>? getStringList(String key) => _data[key] as List<String>?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Set<String> getKeys() => _data.keys.toSet();

  // Unsupported operations - return defaults
  List<bool> getBoolList(String key) => [];
  List<double> getDoubleList(String key) => [];
  List<int> getIntList(String key) => [];
  @override
  Future<bool> commit() async => true;
  @override
  Future<void> reload() async {}

  // The 'get' method is required by SharedPreferences interface
  @override
  Object? get(String key) => _data[key];
}

/// Setup common mock behaviors for SerialPortServiceInterface
///
/// Call this in test setup to configure default mock responses.
void setupMockSerialPortService(MockSerialPortService mock) {
  // Default: successful open
  when(() => mock.open(any())).thenAnswer((_) async {
    return FakeSerialPortSession();
  });

  // Default: successful close
  when(() => mock.close(any())).thenAnswer((_) async {});

  // Default: available ports
  when(() => mock.getAvailablePorts())
      .thenAnswer((_) async => ['COM1', 'COM2']);
}

/// Register fallback values for mocktail
///
/// Call this in setUpAll() to register fallback values
/// for parameterized mock calls.
void registerFallbackValues() {
  // Register SerialConfig fallback
  registerFallbackValue(
    SerialConfig(
      portName: 'COM1',
      baudRate: 9600,
      dataBits: 8,
      parity: 0, // SerialPortParity.none
      stopBits: 1,
      autoReconnect: true,
    ),
  );

  // Register Uint8List fallback
  registerFallbackValue(Uint8List(0));

  // Register SerialPortSession fallback
  registerFallbackValue(FakeSerialPortSession());
}
