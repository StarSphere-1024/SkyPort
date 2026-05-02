import 'package:flutter/material.dart' hide ConnectionState;

import 'serial_config.dart';
import 'connection_status.dart';

/// 统一的串口状态（单一数据源）
@immutable
class SerialPortState {
  final SerialConfig targetConfig;           // 用户设置的配置（立即更新）
  final ConnectionStatus connection;         // 连接状态
  final List<String> availablePorts;         // 可用端口列表
  final bool isReconciling;                  // 是否正在调和（用于UI显示）

  const SerialPortState({
    required this.targetConfig,
    required this.connection,
    required this.availablePorts,
    this.isReconciling = false,
  });

  /// 计算属性：当前显示的波特率
  /// 连接时显示 applied，未连接时显示 target
  int get displayBaudRate =>
      connection.appliedConfig?.baudRate ?? targetConfig.baudRate;

  /// 计算属性：配置是否已同步
  bool get isInSync =>
      connection.state == ConnectionState.connected &&
      connection.appliedConfig?.isSameSettings(targetConfig) == true;

  /// 计算属性：是否正在处理中
  bool get isBusy =>
      connection.state == ConnectionState.connecting ||
      connection.state == ConnectionState.reconfiguring ||
      connection.state == ConnectionState.disconnecting;

  SerialPortState copyWith({
    SerialConfig? targetConfig,
    ConnectionStatus? connection,
    List<String>? availablePorts,
    bool? isReconciling,
  }) {
    return SerialPortState(
      targetConfig: targetConfig ?? this.targetConfig,
      connection: connection ?? this.connection,
      availablePorts: availablePorts ?? this.availablePorts,
      isReconciling: isReconciling ?? this.isReconciling,
    );
  }
}
