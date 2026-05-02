import 'serial_config.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconfiguring,
  disconnecting,
  reconnecting,
}

class ConnectionStatus {
  final ConnectionState state;
  final SerialConfig? appliedConfig;
  final DateTime? connectedAt;
  final String? errorMessage;
  final int rxBytes;
  final int txBytes;
  final int lastRxBytes;

  const ConnectionStatus({
    this.state = ConnectionState.disconnected,
    this.appliedConfig,
    this.connectedAt,
    this.errorMessage,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastRxBytes = 0,
  });

  ConnectionStatus copyWith({
    ConnectionState? state,
    Object? appliedConfig = _unset,
    Object? connectedAt = _unset,
    Object? errorMessage = _unset,
    int? rxBytes,
    int? txBytes,
    int? lastRxBytes,
  }) {
    return ConnectionStatus(
      state: state ?? this.state,
      appliedConfig: identical(appliedConfig, _unset)
          ? this.appliedConfig
          : appliedConfig as SerialConfig?,
      connectedAt: identical(connectedAt, _unset)
          ? this.connectedAt
          : connectedAt as DateTime?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      lastRxBytes: lastRxBytes ?? this.lastRxBytes,
    );
  }
}

const Object _unset = Object();
