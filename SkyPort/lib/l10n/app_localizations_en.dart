// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SkyPort';

  @override
  String get serialPortSettings => 'Serial Port Settings';

  @override
  String get portName => 'Port Name';

  @override
  String get noPortsFound => 'No ports found';

  @override
  String get loadingPorts => 'Loading ports...';

  @override
  String get errorLoadingPorts => 'Error loading ports';

  @override
  String get open => 'Open';

  @override
  String get close => 'Close';

  @override
  String get baudRate => 'Baud Rate';

  @override
  String get dataBits => 'Data Bits';

  @override
  String get parity => 'Parity';

  @override
  String get parityNone => 'None';

  @override
  String get parityOdd => 'Odd';

  @override
  String get parityEven => 'Even';

  @override
  String get stopBits => 'Stop Bits';

  @override
  String get receiveSettings => 'Receive Settings';

  @override
  String get hexDisplay => 'Hex Display';

  @override
  String get showTimestamp => 'Show Timestamp';

  @override
  String get showSent => 'Show Sent Data';

  @override
  String get receiveMode => 'Receive mode';

  @override
  String get clearReceiveArea => 'Clear Receive Area';

  @override
  String get sendSettings => 'Send Settings';

  @override
  String get hexSend => 'Hex Send';

  @override
  String get appendNewline => 'Append newline';

  @override
  String get newlineMode => 'Newline';

  @override
  String get loadMore => 'Load More';

  @override
  String get enterDataToSend => 'Enter data to send';

  @override
  String get invalidHexChars => 'Invalid characters. Use 0-9, A-F.';

  @override
  String get hexEvenLength => 'Hex string must have an even length.';

  @override
  String get send => 'Send';

  @override
  String get txLabel => 'TX';

  @override
  String get rxLabel => 'RX';

  @override
  String connectedStatus(String port, int baud) {
    return 'Connected to $port@$baud';
  }

  @override
  String get connecting => 'Connecting...';

  @override
  String get disconnecting => 'Disconnecting...';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get unavailable => 'Unavailable';

  @override
  String trafficStats(int rx, int tx, int lastRx) {
    return 'Rx: $rx - $lastRx | Tx: $tx';
  }

  @override
  String get trafficStatsTooltip =>
      'Total received bytes - Last packet size | Total sent bytes';

  @override
  String get timeoutLabel => 'Block Interval';

  @override
  String get receiveModeTooltip =>
      'Line: Split data when newline is received\nBlock: Split data when no data received for set time';

  @override
  String get receiveModeTooltipHex =>
      'Line mode not available in Hex display\nBlock: Split data when no data received for set time';

  @override
  String get lineModeLabel => 'Line';

  @override
  String get blockModeLabel => 'Block';
}
