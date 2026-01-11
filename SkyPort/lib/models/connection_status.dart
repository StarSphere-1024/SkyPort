import '../services/serial_port_service.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting
}

class SerialConnection {
  final ConnectionStatus status;
  final SerialPortSession? session;
  final int rxBytes;
  final int txBytes;

  SerialConnection({
    this.status = ConnectionStatus.disconnected,
    this.session,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastRxBytes = 0,
  });

  final int lastRxBytes;

  SerialConnection copyWith({
    ConnectionStatus? status,
    SerialPortSession? session,
    int? rxBytes,
    int? txBytes,
    int? lastRxBytes,
  }) {
    return SerialConnection(
      status: status ?? this.status,
      session: session ?? this.session,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      lastRxBytes: lastRxBytes ?? this.lastRxBytes,
    );
  }
}
