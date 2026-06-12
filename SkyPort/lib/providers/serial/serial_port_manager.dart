import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_error.dart';
import '../../models/connection_status.dart';
import '../../models/serial_config.dart';
import '../../models/serial_port_state.dart';
import '../../models/ui_settings.dart';
import '../../services/serial_port_service.dart';
import '../../utils/constants.dart';
import '../../utils/hex_parser.dart';
import '../common_providers.dart';
import 'data_log_provider.dart';
import 'error_provider.dart';
import 'ui_settings_provider.dart';

final serialPortManagerProvider =
    NotifierProvider<SerialPortManager, SerialPortState>(() {
  return SerialPortManager();
});

final serialPortServiceProvider = Provider<SerialPortServiceInterface>((ref) {
  return SerialPortService();
});

class SerialPortManager extends Notifier<SerialPortState> {
  late final SerialPortServiceInterface _service;
  late final SharedPreferences _prefs;

  StreamSubscription<Uint8List>? _dataSub;
  SerialPortSessionInterface? _session;
  Timer? _portPollTimer;
  Timer? _reconnectTimer;

  bool _isReconciling = false;
  bool _isDisposed = false;
  int _operationToken = 0;

  @override
  SerialPortState build() {
    _isDisposed = false;
    _service = ref.read(serialPortServiceProvider);
    _prefs = ref.read(sharedPreferencesProvider);

    ref.onDispose(() {
      _isDisposed = true;
      _invalidatePendingOperations();
      _stopReconnectTimer();
      _portPollTimer?.cancel();
      unawaited(_cleanupOnDispose());
    });

    final initialState = _loadInitialState(_prefs);
    unawaited(_refreshAvailablePorts());
    _startPortPolling();
    return initialState;
  }

  void updateConfig(SerialConfig newConfig) {
    if (_isDisposed) return;

    _saveConfig(newConfig);
    state = state.copyWith(targetConfig: newConfig);

    if (state.connection.state == ConnectionState.connected ||
        state.connection.state == ConnectionState.reconfiguring) {
      unawaited(_triggerReconciliation());
      return;
    }

    if (state.connection.state == ConnectionState.reconnecting) {
      unawaited(_refreshAvailablePorts());
    }
  }

  void setPortName(String portName) {
    updateConfig(state.targetConfig.copyWith(portName: portName));
  }

  void setBaudRate(int baudRate) {
    updateConfig(state.targetConfig.copyWith(baudRate: baudRate));
  }

  void setDataBits(int dataBits) {
    updateConfig(state.targetConfig.copyWith(dataBits: dataBits));
  }

  void setParity(int parity) {
    updateConfig(state.targetConfig.copyWith(parity: parity));
  }

  void setStopBits(int stopBits) {
    updateConfig(state.targetConfig.copyWith(stopBits: stopBits));
  }

  void setAutoReconnect(bool value) {
    updateConfig(state.targetConfig.copyWith(autoReconnect: value));
  }

  Future<void> connect() async {
    if (_isDisposed || _isBusy) return;
    await _openTargetConfig(
      pendingState: ConnectionState.connecting,
      allowReconnectOnFailure: false,
    );
  }

  Future<void> disconnect() async {
    if (_isDisposed || state.connection.state == ConnectionState.disconnected) {
      return;
    }

    final token = _nextOperationToken();
    _stopReconnectTimer();
    _setConnectionState(ConnectionState.disconnecting);
    await _cleanup();

    if (!_shouldApplyOperation(token)) {
      return;
    }

    _setDisconnectedState();
  }

  Future<void> send(String data) async {
    if (_isDisposed) return;
    if (_session == null ||
        state.connection.state != ConnectionState.connected) {
      return;
    }

    ref.read(errorProvider.notifier).clear();
    final uiSettings = ref.read(uiSettingsProvider);
    Uint8List bytesToSend;

    try {
      if (uiSettings.hexSend) {
        bytesToSend = hexToBytes(data);
      } else {
        var textToSend = data;
        if (uiSettings.appendNewline) {
          switch (uiSettings.newlineMode) {
            case NewlineMode.lf:
              textToSend = '$textToSend\n';
              break;
            case NewlineMode.cr:
              textToSend = '$textToSend\r';
              break;
            case NewlineMode.crlf:
              textToSend = '$textToSend\r\n';
              break;
          }
        }
        bytesToSend = Uint8List.fromList(utf8.encode(textToSend));
      }
    } catch (_) {
      ref.read(errorProvider.notifier).setError(AppErrorType.invalidHexFormat);
      return;
    }

    try {
      final bytesWritten = _session!.write(
        bytesToSend,
        timeoutMs: SkyPortConstants.defaultWriteTimeoutMs,
      );
      if (bytesWritten > 0) {
        ref
            .read(dataLogProvider.notifier)
            .addSent(bytesToSend.sublist(0, bytesWritten));
      }
      state = state.copyWith(
        connection: state.connection.copyWith(
          txBytes: state.connection.txBytes + bytesWritten,
        ),
      );
    } on SerialPortWriteException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.writeFailed, e.message);
    }
  }

  void resetStats() {
    if (_isDisposed) return;

    state = state.copyWith(
      connection: state.connection.copyWith(
        rxBytes: 0,
        txBytes: 0,
        lastRxBytes: 0,
      ),
    );
  }

  Future<void> _triggerReconciliation() async {
    if (_isReconciling || _isDisposed) return;

    _isReconciling = true;
    state = state.copyWith(isReconciling: true);
    final token = _nextOperationToken();

    try {
      while (!_isDisposed &&
          _shouldApplyOperation(token) &&
          !_isConfigApplied(state.targetConfig)) {
        final configToApply = state.targetConfig;
        _setConnectionState(ConnectionState.reconfiguring);

        try {
          await _cleanup();
          if (!_shouldApplyOperation(token)) {
            break;
          }

          final session = await _service.open(configToApply);
          if (!_shouldApplyOperation(token)) {
            await session.dispose();
            break;
          }

          _onConnected(session, configToApply);
        } catch (e) {
          if (_shouldApplyOperation(token)) {
            _onConnectError(e);
          }
          break;
        }
      }
    } finally {
      _isReconciling = false;
      if (!_isDisposed) {
        state = state.copyWith(isReconciling: false);
      }
    }
  }

  Future<void> _openTargetConfig({
    required ConnectionState pendingState,
    required bool allowReconnectOnFailure,
  }) async {
    final token = _nextOperationToken();
    final configToOpen = state.targetConfig;
    _setConnectionState(pendingState);

    try {
      final session = await _service.open(configToOpen);
      if (!_shouldApplyOperation(token)) {
        await session.dispose();
        return;
      }
      _onConnected(session, configToOpen);
    } catch (e) {
      if (!_shouldApplyOperation(token)) {
        return;
      }

      if (allowReconnectOnFailure && configToOpen.autoReconnect) {
        _enterReconnectingState(e.toString());
        _reportPortDisconnected(e);
      } else {
        _onConnectError(e);
      }
    }
  }

  Future<void> _handleConnectionLoss(Object error) async {
    if (_isDisposed) return;

    final shouldReconnect = state.connection.appliedConfig?.autoReconnect ??
        state.targetConfig.autoReconnect;
    _invalidatePendingOperations();
    await _cleanup();

    if (_isDisposed) return;

    if (shouldReconnect) {
      _enterReconnectingState(error.toString());
      _reportPortDisconnected(error);
      unawaited(_refreshAvailablePorts());
    } else {
      _reportPortDisconnected(error);
      _setDisconnectedState(errorMessage: error.toString());
    }
  }

  Future<void> _attemptReconnect() async {
    if (_isDisposed ||
        _isBusy ||
        state.connection.state != ConnectionState.reconnecting) {
      return;
    }

    final targetPort = state.targetConfig.portName;
    if (targetPort.isEmpty || !state.availablePorts.contains(targetPort)) {
      _startReconnectTimer();
      return;
    }

    await _openTargetConfig(
      pendingState: ConnectionState.connecting,
      allowReconnectOnFailure: true,
    );
  }

  void _onConnected(
    SerialPortSessionInterface session,
    SerialConfig appliedConfig,
  ) {
    _stopReconnectTimer();
    _session = session;
    _dataSub = session.stream.listen(
      (data) {
        ref.read(dataLogProvider.notifier).addReceived(data);
        _onDataReceived(data);
      },
      onError: (error) {
        unawaited(_handleConnectionLoss(error));
      },
    );

    state = state.copyWith(
      connection: state.connection.copyWith(
        state: ConnectionState.connected,
        appliedConfig: appliedConfig,
        connectedAt: DateTime.now(),
        errorMessage: null,
      ),
    );
  }

  void _onConnectError(Object error) {
    _stopReconnectTimer();
    _reportConnectionError(error);
    state = state.copyWith(
      connection: state.connection.copyWith(
        state: ConnectionState.disconnected,
        appliedConfig: null,
        connectedAt: null,
        errorMessage: error.toString(),
      ),
    );
  }

  void _onDataReceived(Uint8List data) {
    state = state.copyWith(
      connection: state.connection.copyWith(
        rxBytes: state.connection.rxBytes + data.length,
        lastRxBytes: data.length,
      ),
    );
  }

  Future<void> _refreshAvailablePorts() async {
    try {
      final ports = await _service.getAvailablePorts();
      if (_isDisposed) return;

      if (!_samePorts(state.availablePorts, ports)) {
        state = state.copyWith(availablePorts: List.unmodifiable(ports));
      }

      if (state.connection.state == ConnectionState.reconnecting &&
          ports.contains(state.targetConfig.portName)) {
        unawaited(_attemptReconnect());
      }
    } catch (_) {
      // Ignore port enumeration failures and keep the previous list.
    }
  }

  Future<void> _cleanup() async {
    await _dataSub?.cancel();
    _dataSub = null;

    if (_session != null) {
      await _service.close(_session);
      _session = null;
    }

    await Future.delayed(
      const Duration(milliseconds: SkyPortConstants.connectionSettleDelayMs),
    );
  }

  Future<void> _cleanupOnDispose() async {
    await _dataSub?.cancel();
    _dataSub = null;

    if (_session != null) {
      try {
        await _session!.dispose();
      } catch (_) {}
      _session = null;
    }
  }

  bool _isConfigApplied(SerialConfig target) {
    final applied = state.connection.appliedConfig;
    if (applied == null) return false;
    return applied.isSameSettings(target);
  }

  bool get _isBusy =>
      state.connection.state == ConnectionState.connecting ||
      state.connection.state == ConnectionState.reconfiguring ||
      state.connection.state == ConnectionState.disconnecting;

  void _setConnectionState(ConnectionState newState) {
    state = state.copyWith(
      connection: state.connection.copyWith(state: newState),
    );
  }

  void _setDisconnectedState({String? errorMessage}) {
    _stopReconnectTimer();
    final currentStats = state.connection;
    state = state.copyWith(
      connection: ConnectionStatus(
        state: ConnectionState.disconnected,
        errorMessage: errorMessage,
        rxBytes: currentStats.rxBytes,
        txBytes: currentStats.txBytes,
        lastRxBytes: currentStats.lastRxBytes,
      ),
    );
  }

  void _enterReconnectingState(String errorMessage) {
    final currentStats = state.connection;
    state = state.copyWith(
      connection: ConnectionStatus(
        state: ConnectionState.reconnecting,
        errorMessage: errorMessage,
        rxBytes: currentStats.rxBytes,
        txBytes: currentStats.txBytes,
        lastRxBytes: currentStats.lastRxBytes,
      ),
    );
    _startReconnectTimer();
  }

  void _startPortPolling() {
    _portPollTimer?.cancel();
    _portPollTimer = Timer.periodic(
      const Duration(milliseconds: SkyPortConstants.portPollIntervalMs),
      (_) {
        unawaited(_refreshAvailablePorts());
      },
    );
  }

  void _startReconnectTimer() {
    _reconnectTimer ??= Timer.periodic(
      const Duration(milliseconds: SkyPortConstants.portPollIntervalMs),
      (_) {
        unawaited(_refreshAvailablePorts());
      },
    );
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  int _nextOperationToken() {
    _operationToken += 1;
    return _operationToken;
  }

  void _invalidatePendingOperations() {
    _operationToken += 1;
  }

  bool _shouldApplyOperation(int token) {
    return !_isDisposed && token == _operationToken;
  }

  void _saveConfig(SerialConfig config) {
    _prefs.setString('serial_port_name', config.portName);
    _prefs.setInt('serial_baud_rate', config.baudRate);
    _prefs.setInt('serial_data_bits', config.dataBits);
    _prefs.setInt('serial_parity', config.parity);
    _prefs.setInt('serial_stop_bits', config.stopBits);
    _prefs.setBool('serial_auto_reconnect', config.autoReconnect);
  }

  bool _samePorts(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setA = Set<String>.from(a);
    final setB = Set<String>.from(b);
    return setA.length == setB.length && setA.containsAll(setB);
  }

  void _reportConnectionError(Object error) {
    final notifier = ref.read(errorProvider.notifier);
    if (error is SerialPortOpenTimeoutException) {
      notifier.setError(AppErrorType.portOpenTimeout, error.message);
    } else if (error is SerialPortOpenException) {
      notifier.setError(AppErrorType.portOpenFailed, error.message);
    } else {
      notifier.setError(AppErrorType.unknown, error.toString());
    }
  }

  void _reportPortDisconnected(Object error) {
    ref
        .read(errorProvider.notifier)
        .setError(AppErrorType.portDisconnected, error.toString());
  }
}

SerialPortState _loadInitialState(SharedPreferences prefs) {
  final config = SerialConfig(
    portName: prefs.getString('serial_port_name') ?? '',
    baudRate: prefs.getInt('serial_baud_rate') ?? 9600,
    dataBits: prefs.getInt('serial_data_bits') ?? 8,
    parity: prefs.getInt('serial_parity') ?? 0,
    stopBits: prefs.getInt('serial_stop_bits') ?? 1,
    autoReconnect: prefs.getBool('serial_auto_reconnect') ?? true,
  );

  return SerialPortState(
    targetConfig: config,
    connection: const ConnectionStatus(),
    availablePorts: const [],
  );
}
