// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'SkyPort';

  @override
  String get serialPortSettings => '串口设置';

  @override
  String get portName => '端口';

  @override
  String get noPortsFound => '未发现端口';

  @override
  String get loadingPorts => '正在加载端口...';

  @override
  String get errorLoadingPorts => '加载端口出错';

  @override
  String get open => '打开';

  @override
  String get close => '关闭';

  @override
  String get baudRate => '波特率';

  @override
  String get dataBits => '数据位';

  @override
  String get parity => '校验位';

  @override
  String get parityNone => '无';

  @override
  String get parityOdd => '奇';

  @override
  String get parityEven => '偶';

  @override
  String get stopBits => '停止位';

  @override
  String get receiveSettings => '接收设置';

  @override
  String get hexDisplay => '十六进制显示';

  @override
  String get showTimestamp => '显示时间戳';

  @override
  String get showSent => '显示发送数据';

  @override
  String get frameIntervalMs => '断帧间隔 (ms)';

  @override
  String get autoFrameBreak => '自动断帧';

  @override
  String get frameBreakTimeMs => '断帧时间 (ms)';

  @override
  String get clearReceiveArea => '清空接收区';

  @override
  String get sendSettings => '发送设置';

  @override
  String get hexSend => '十六进制发送';

  @override
  String get appendNewline => '添加换行符';

  @override
  String get newlineMode => '换行符';

  @override
  String get loadMore => '加载更多';

  @override
  String get enterDataToSend => '输入要发送的数据';

  @override
  String get invalidHexChars => '字符不合法，仅允许 0-9 与 A-F';

  @override
  String get hexEvenLength => 'Hex 字符串长度必须为偶数';

  @override
  String get send => '发送';

  @override
  String get txLabel => '发送';

  @override
  String get rxLabel => '接收';

  @override
  String connectedStatus(String port, int baud) {
    return '已连接 $port@$baud';
  }

  @override
  String get connecting => '连接中...';

  @override
  String get disconnecting => '断开中...';

  @override
  String get disconnected => '未连接';

  @override
  String get unavailable => '不可用';

  @override
  String trafficStats(int rx, int tx) {
    return '接收: $rx | 发送: $tx';
  }
}
