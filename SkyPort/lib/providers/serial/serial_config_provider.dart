import 'dart:async';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/serial_config.dart';
import '../common_providers.dart';
import '../../services/serial_port_service.dart';

// Helper to compare port lists
bool _arePortListsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final setA = Set.of(a);
  final setB = Set.of(b);
  return setA.length == setB.length && setA.containsAll(setB);
}

// Provider for SerialPortServiceInterface
final serialPortServiceProvider = Provider<SerialPortServiceInterface>((ref) {
  return SerialPortService(); // Production implementation
});

final availablePortsProvider =
    StreamProvider.autoDispose<List<String>>((ref) async* {
  ref.keepAlive(); // Keep alive for some time after last listener is removed

  final service = ref.read(serialPortServiceProvider);
  List<String> currentPorts = await service.getAvailablePorts();
  yield currentPorts;

  final timer = Stream.periodic(const Duration(milliseconds: 500));
  await for (final _ in timer) {
    final newPorts = await service.getAvailablePorts();
    if (!_arePortListsEqual(currentPorts, newPorts)) {
      currentPorts = newPorts;
      yield currentPorts;
    }
  }
});

class SerialConfigNotifier extends Notifier<SerialConfig?> {
  static const _keyPortName = 'serial_port_name';
  static const _keyBaudRate = 'serial_baud_rate';
  static const _keyDataBits = 'serial_data_bits';
  static const _keyParity = 'serial_parity';
  static const _keyStopBits = 'serial_stop_bits';
  static const _keyAutoReconnect = 'serial_auto_reconnect';

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

    // For initial load, try to restore from prefs
    final savedPort = prefs.getString(_keyPortName);
    if (savedPort != null) {
      // Always restore saved port if it exists
      return _loadConfigFromPrefs(prefs, savedPort);
    }

    // If no saved port, we'll wait for ports to become available via the listener above
    return null;
  }

  SerialConfig _loadConfigFromPrefs(SharedPreferences prefs, String portName) {
    return SerialConfig(
      portName: portName,
      baudRate: prefs.getInt(_keyBaudRate) ?? 9600,
      dataBits: prefs.getInt(_keyDataBits) ?? 8,
      parity: prefs.getInt(_keyParity) ?? SerialPortParity.none,
      stopBits: prefs.getInt(_keyStopBits) ?? 1,
      autoReconnect: prefs.getBool(_keyAutoReconnect) ?? true,
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
      prefs.setBool(_keyAutoReconnect, config.autoReconnect);
    }
  }

  void setPort(String portName) {
    state =
        state?.copyWith(portName: portName) ?? SerialConfig(portName: portName);
    _saveConfig();
  }

  void setBaudRate(int baudRate) {
    if (state == null) {
      // If no config exists, create one with default values and the new baud rate
      state = SerialConfig(
        portName: '', // Will be set later
        baudRate: baudRate,
        dataBits: 8,
        parity: SerialPortParity.none,
        stopBits: 1,
        autoReconnect: true,
      );
    } else {
      state = state!.copyWith(baudRate: baudRate);
    }
    _saveConfig();
  }

  void setDataBits(int dataBits) {
    if (state == null) {
      state = SerialConfig(
        portName: '',
        baudRate: 9600,
        dataBits: dataBits,
        parity: SerialPortParity.none,
        stopBits: 1,
        autoReconnect: true,
      );
    } else {
      state = state!.copyWith(dataBits: dataBits);
    }
    _saveConfig();
  }

  void setParity(int parity) {
    if (state == null) {
      state = SerialConfig(
        portName: '',
        baudRate: 9600,
        dataBits: 8,
        parity: parity,
        stopBits: 1,
        autoReconnect: true,
      );
    } else {
      state = state!.copyWith(parity: parity);
    }
    _saveConfig();
  }

  void setStopBits(int stopBits) {
    if (state == null) {
      state = SerialConfig(
        portName: '',
        baudRate: 9600,
        dataBits: 8,
        parity: SerialPortParity.none,
        stopBits: stopBits,
        autoReconnect: true,
      );
    } else {
      state = state!.copyWith(stopBits: stopBits);
    }
    _saveConfig();
  }

  void setAutoReconnect(bool value) {
    if (state == null) {
      state = SerialConfig(
        portName: '',
        baudRate: 9600,
        dataBits: 8,
        parity: SerialPortParity.none,
        stopBits: 1,
        autoReconnect: value,
      );
    } else {
      state = state!.copyWith(autoReconnect: value);
    }
    _saveConfig();
  }
}

final serialConfigProvider =
    NotifierProvider.autoDispose<SerialConfigNotifier, SerialConfig?>(
        SerialConfigNotifier.new);
