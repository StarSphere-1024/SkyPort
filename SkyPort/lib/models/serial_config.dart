import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialConfig {
  final String portName;
  final int baudRate;
  final int dataBits;
  final int parity;
  final int stopBits;
  final bool autoReconnect;

  SerialConfig({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = SerialPortParity.none,
    this.stopBits = 1,
    this.autoReconnect = true,
  });

  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    int? parity,
    int? stopBits,
    bool? autoReconnect,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      parity: parity ?? this.parity,
      stopBits: stopBits ?? this.stopBits,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}
