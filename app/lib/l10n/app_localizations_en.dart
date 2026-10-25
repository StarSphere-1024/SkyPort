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
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close window';

  @override
  String get serialPageLabel => 'Port';

  @override
  String get settingsPageLabel => 'Settings';

  @override
  String get expandConfiguration => 'Expand configuration panel';

  @override
  String get collapseConfiguration => 'Collapse configuration panel';

  @override
  String get noPortSelected => 'No port selected';

  @override
  String get serialPortSettings => 'Serial Port Settings';

  @override
  String get portName => 'Port Name';

  @override
  String get noPortsFound => 'No ports found';

  @override
  String get open => 'Open';

  @override
  String get close => 'Close';

  @override
  String get baudRate => 'Baud Rate';

  @override
  String get flowControl => 'Flow Control';

  @override
  String get flowControlNone => 'None';

  @override
  String get flowControlHardware => 'RTS/CTS';

  @override
  String get flowControlSoftware => 'XON/XOFF';

  @override
  String get flowControlSoftwareWarning =>
      'With XON/XOFF enabled, receiving 0x13 pauses outbound transmission and receiving 0x11 resumes it. These control bytes are unsuitable for transparent binary transfer.';

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
  String get enterDataToSend => 'Enter data to send';

  @override
  String get invalidHexChars => 'Invalid characters. Use 0-9, A-F.';

  @override
  String get hexEvenLength => 'Hex string must have an even length.';

  @override
  String get send => 'Send';

  @override
  String get rxLabel => 'RX';

  @override
  String get connected => 'Connected';

  @override
  String get connecting => 'Connecting...';

  @override
  String get disconnecting => 'Disconnecting...';

  @override
  String get reconnecting => 'Waiting for device...';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get autoReconnect => 'Smart Reconnect';

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
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsLogs => 'Logs';

  @override
  String get logBufferSizeHint => '16–512 MB · Press Enter to apply';

  @override
  String get theme => 'Theme';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get dynamicColor => 'Use system accent color';

  @override
  String get themeColorSaveFailed => 'Could not save theme preference';

  @override
  String get colorScheme => 'Color scheme';

  @override
  String get themeBlue => 'Default blue';

  @override
  String get themeRed => 'Red';

  @override
  String get themeGreen => 'Green';

  @override
  String get themeTeal => 'Teal';

  @override
  String get themeIndigo => 'Indigo';

  @override
  String get themeViolet => 'Violet';

  @override
  String get themePink => 'Pink';

  @override
  String get themeYellow => 'Yellow';

  @override
  String get themeOrange => 'Orange';

  @override
  String get customSeedColor => 'Custom seed color';

  @override
  String get seedColorHex => 'Seed color (#RRGGBB)';

  @override
  String get seedColorHexError =>
      'Enter #RRGGBB (six hexadecimal digits, no alpha).';

  @override
  String get colorChannelRed => 'Red channel';

  @override
  String get colorChannelGreen => 'Green channel';

  @override
  String get colorChannelBlue => 'Blue channel';

  @override
  String get applyColor => 'Apply';

  @override
  String get followSystem => 'Follow System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get logBufferSize => 'Log Buffer Size';

  @override
  String get logBufferSizeError => '16-512';

  @override
  String get enableAnsi => 'Enable ANSI';

  @override
  String get autoSend => 'Auto Send';

  @override
  String get secondsUnit => 's';

  @override
  String get exportLogs => 'Export Logs';

  @override
  String get exportPath => 'Export path';

  @override
  String get exportPathHint => 'Default folder for exported logs';

  @override
  String get logsExportedTo => 'Logs exported to: ';

  @override
  String exportFailed(String message) {
    return 'Export failed: $message';
  }

  @override
  String writeFailure(int bytes, String message) {
    return 'Write failed after $bytes bytes: $message';
  }

  @override
  String autoSendPaused(String message) {
    return 'Auto-send paused: $message';
  }

  @override
  String get applyingConfiguration => 'Applying configuration...';

  @override
  String get logDataGap =>
      'Some log events were missed; the view has been resynchronized.';

  @override
  String logTrimmed(int records, int bytes) {
    return 'Older records trimmed: $records records / $bytes bytes';
  }

  @override
  String get startupFailed => 'SkyPort could not start';

  @override
  String get errorInvalidArgument => 'Invalid argument';

  @override
  String get errorPortNotFound => 'Port not found';

  @override
  String get errorOpenFailed => 'Port open failed';

  @override
  String get errorPermissionDenied => 'Permission denied';

  @override
  String get errorUnsupportedConfiguration => 'Unsupported configuration';

  @override
  String get errorReadFailed => 'Serial read failed';

  @override
  String get errorDisconnected => 'Serial connection lost';

  @override
  String get errorTimeout => 'Operation timed out';

  @override
  String get errorClosed => 'Application core is closed';

  @override
  String get errorQueueOverflow => 'Queue capacity exceeded';

  @override
  String get errorTaskFailed => 'Background task failed';

  @override
  String get errorInternal => 'Internal error';

  @override
  String get logIncomplete =>
      'The retained log contains a serial data or session gap.';

  @override
  String get diagnosticDetails => 'Diagnostic details';

  @override
  String get errorWriteFailed => 'Serial write failed';

  @override
  String get errorPortNameRequired => 'Select a serial port.';

  @override
  String get errorPortNameTooLong =>
      'The port name must not exceed 4096 bytes.';

  @override
  String get errorPortNameInvalid =>
      'The port name must not contain NUL or line breaks.';

  @override
  String get errorBaudRateInvalid => 'The baud rate must be greater than zero.';

  @override
  String get errorDataBitsInvalid => 'Data bits must be between 5 and 8.';

  @override
  String get errorStopBitsInvalid => 'Stop bits must be 1 or 2.';

  @override
  String get errorLegacyConfigInvalid =>
      'The previous application\'s serial settings are invalid.';

  @override
  String get errorConfigVersionUnsupported =>
      'This configuration version is not supported.';

  @override
  String get errorNewlineInvalid =>
      'The stored newline must be LF, CR, or CRLF.';

  @override
  String get errorAutoSendIntervalInvalid =>
      'The auto-send interval must be between 0.01 and 60 seconds.';

  @override
  String get errorLogCapacityInvalid =>
      'The log buffer size must be between 16 and 512 MiB.';

  @override
  String get errorHistoryTooLong => 'Send history must not exceed 100 entries.';

  @override
  String get errorHistoryEntryEmpty =>
      'Send history must not contain empty entries.';

  @override
  String get errorHistoryTooLarge => 'Send history must not exceed 1 MiB.';

  @override
  String get errorConfigTooLarge =>
      'The configuration file must not exceed 8 MiB.';

  @override
  String get errorConfigInvalid => 'The configuration file is invalid.';

  @override
  String get errorConfigIo =>
      'The configuration file could not be read or saved.';

  @override
  String get errorSendTooLarge => 'Each transmission must not exceed 1 MiB.';

  @override
  String get errorSendInputTooLarge => 'Send input must not exceed 2 MiB.';

  @override
  String get errorAutoSendTooLarge => 'Auto-send data must not exceed 1 MiB.';

  @override
  String get errorSendEmpty => 'Enter data to send.';

  @override
  String get errorNoLogsToExport =>
      'No retained log records match the export options.';

  @override
  String get errorExportLog => 'The log file could not be written.';

  @override
  String get errorQueueCapacityInvalid =>
      'Queue capacities must be between 1 and 4096.';

  @override
  String get errorBridgeInitialization =>
      'The serial core component could not be loaded. Check that the application installation is complete.';

  @override
  String get errorPreferenceMigration =>
      'The migration status of the previous settings could not be saved.';

  @override
  String get errorPreferencesUnavailable =>
      'The application settings could not be loaded.';

  @override
  String get errorFileAccess =>
      'A required file or folder could not be accessed.';

  @override
  String get errorPluginUnavailable =>
      'A required platform service is unavailable.';

  @override
  String get errorPlatform => 'A system service call failed.';

  @override
  String get errorPlatformUnsupported => 'This platform is not supported.';

  @override
  String get errorUnexpected =>
      'An unexpected error occurred. See diagnostic details.';
}
