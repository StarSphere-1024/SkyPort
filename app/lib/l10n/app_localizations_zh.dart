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
  String get reconnecting => '等待设备...';

  @override
  String get disconnected => '未连接';

  @override
  String get autoReconnect => '智能重连';

  @override
  String get unavailable => '不可用';

  @override
  String trafficStats(int rx, int tx, int lastRx) {
    return '接收: $rx - $lastRx | 发送: $tx';
  }

  @override
  String get trafficStatsTooltip => '累计接收字节数 - 上次包大小 | 累计发送字节数';

  @override
  String get timeoutLabel => '块间隔';

  @override
  String get settingsTitle => '设置';

  @override
  String get theme => '主题';

  @override
  String get themeColor => '主题颜色';

  @override
  String get followSystem => '跟随系统';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get logBufferSize => '日志缓冲区大小';

  @override
  String get logBufferSizeError => '16-512之间的整数';

  @override
  String get enableAnsi => '启用 ANSI';

  @override
  String get autoSend => '自动发送';

  @override
  String get autoSendInterval => '间隔';

  @override
  String get autoSendIntervalError => '0.01-60';

  @override
  String get autoSendHint => '自动发送间隔（秒）';

  @override
  String get secondsUnit => '秒';

  @override
  String get exportLogs => '导出日志';

  @override
  String get exportPath => '导出路径';

  @override
  String get exportPathHint => '日志导出的默认文件夹';

  @override
  String get logsExportedTo => '日志已导出到：';

  @override
  String get exportFailed => '导出失败：';

  @override
  String writeFailure(int bytes, String message) {
    return '写入失败，已发送 $bytes 字节：$message';
  }

  @override
  String autoSendPaused(String message) {
    return '自动发送已暂停：$message';
  }

  @override
  String get importFile => '导入文件';

  @override
  String get applyingConfiguration => '正在应用配置...';

  @override
  String get logDataGap => '部分日志事件丢失；视图已重新同步。';

  @override
  String logTrimmed(int records, int bytes) {
    return '已清除较早记录：$records 条记录 / $bytes 字节';
  }

  @override
  String get startupFailed => 'SkyPort 无法启动';

  @override
  String get errorInvalidArgument => '参数无效';

  @override
  String get errorPortNotFound => '未找到串口';

  @override
  String get errorOpenFailed => '串口打开失败';

  @override
  String get errorPermissionDenied => '权限不足';

  @override
  String get errorUnsupportedConfiguration => '不支持此配置';

  @override
  String get errorReadFailed => '串口读取失败';

  @override
  String get errorDisconnected => '串口连接丢失';

  @override
  String get errorTimeout => '操作超时';

  @override
  String get errorClosed => '应用核心已关闭';

  @override
  String get errorQueueOverflow => '队列容量已满';

  @override
  String get errorTaskFailed => '后台任务失败';

  @override
  String get errorInternal => '内部错误';

  @override
  String get logIncomplete => '当前保留的日志存在串口数据或会话缺口。';
}
