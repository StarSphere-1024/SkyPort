import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SkyPort'**
  String get appTitle;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get windowClose;

  /// No description provided for @serialPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get serialPageLabel;

  /// No description provided for @settingsPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsPageLabel;

  /// No description provided for @expandConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Expand configuration panel'**
  String get expandConfiguration;

  /// No description provided for @collapseConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Collapse configuration panel'**
  String get collapseConfiguration;

  /// No description provided for @noPortSelected.
  ///
  /// In en, this message translates to:
  /// **'No port selected'**
  String get noPortSelected;

  /// No description provided for @serialPortSettings.
  ///
  /// In en, this message translates to:
  /// **'Serial Port Settings'**
  String get serialPortSettings;

  /// No description provided for @portName.
  ///
  /// In en, this message translates to:
  /// **'Port Name'**
  String get portName;

  /// No description provided for @noPortsFound.
  ///
  /// In en, this message translates to:
  /// **'No ports found'**
  String get noPortsFound;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @baudRate.
  ///
  /// In en, this message translates to:
  /// **'Baud Rate'**
  String get baudRate;

  /// No description provided for @flowControl.
  ///
  /// In en, this message translates to:
  /// **'Flow Control'**
  String get flowControl;

  /// No description provided for @flowControlNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get flowControlNone;

  /// No description provided for @flowControlHardware.
  ///
  /// In en, this message translates to:
  /// **'RTS/CTS'**
  String get flowControlHardware;

  /// No description provided for @flowControlSoftware.
  ///
  /// In en, this message translates to:
  /// **'XON/XOFF'**
  String get flowControlSoftware;

  /// No description provided for @flowControlSoftwareWarning.
  ///
  /// In en, this message translates to:
  /// **'With XON/XOFF enabled, receiving 0x13 pauses outbound transmission and receiving 0x11 resumes it. These control bytes are unsuitable for transparent binary transfer.'**
  String get flowControlSoftwareWarning;

  /// No description provided for @dataBits.
  ///
  /// In en, this message translates to:
  /// **'Data Bits'**
  String get dataBits;

  /// No description provided for @parity.
  ///
  /// In en, this message translates to:
  /// **'Parity'**
  String get parity;

  /// No description provided for @parityNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get parityNone;

  /// No description provided for @parityOdd.
  ///
  /// In en, this message translates to:
  /// **'Odd'**
  String get parityOdd;

  /// No description provided for @parityEven.
  ///
  /// In en, this message translates to:
  /// **'Even'**
  String get parityEven;

  /// No description provided for @stopBits.
  ///
  /// In en, this message translates to:
  /// **'Stop Bits'**
  String get stopBits;

  /// No description provided for @receiveSettings.
  ///
  /// In en, this message translates to:
  /// **'Receive Settings'**
  String get receiveSettings;

  /// No description provided for @hexDisplay.
  ///
  /// In en, this message translates to:
  /// **'Hex Display'**
  String get hexDisplay;

  /// No description provided for @showTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Show Timestamp'**
  String get showTimestamp;

  /// No description provided for @showSent.
  ///
  /// In en, this message translates to:
  /// **'Show Sent Data'**
  String get showSent;

  /// No description provided for @clearReceiveArea.
  ///
  /// In en, this message translates to:
  /// **'Clear Receive Area'**
  String get clearReceiveArea;

  /// No description provided for @sendSettings.
  ///
  /// In en, this message translates to:
  /// **'Send Settings'**
  String get sendSettings;

  /// No description provided for @hexSend.
  ///
  /// In en, this message translates to:
  /// **'Hex Send'**
  String get hexSend;

  /// No description provided for @appendNewline.
  ///
  /// In en, this message translates to:
  /// **'Append newline'**
  String get appendNewline;

  /// No description provided for @newlineMode.
  ///
  /// In en, this message translates to:
  /// **'Newline'**
  String get newlineMode;

  /// No description provided for @enterDataToSend.
  ///
  /// In en, this message translates to:
  /// **'Enter data to send'**
  String get enterDataToSend;

  /// No description provided for @invalidHexChars.
  ///
  /// In en, this message translates to:
  /// **'Invalid characters. Use 0-9, A-F.'**
  String get invalidHexChars;

  /// No description provided for @hexEvenLength.
  ///
  /// In en, this message translates to:
  /// **'Hex string must have an even length.'**
  String get hexEvenLength;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @rxLabel.
  ///
  /// In en, this message translates to:
  /// **'RX'**
  String get rxLabel;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @disconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting...'**
  String get disconnecting;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for device...'**
  String get reconnecting;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @autoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Smart Reconnect'**
  String get autoReconnect;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @trafficStats.
  ///
  /// In en, this message translates to:
  /// **'RX: {rx} B | TX: {tx} B'**
  String trafficStats(int rx, int tx);

  /// No description provided for @trafficStatsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Total received bytes · Total sent bytes · Receive rate'**
  String get trafficStatsTooltip;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @settingsLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get settingsLogs;

  /// No description provided for @logBufferSizeHint.
  ///
  /// In en, this message translates to:
  /// **'16–512 MB · Press Enter to apply'**
  String get logBufferSizeHint;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @dynamicColor.
  ///
  /// In en, this message translates to:
  /// **'Use system accent color'**
  String get dynamicColor;

  /// No description provided for @themeColorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save theme preference'**
  String get themeColorSaveFailed;

  /// No description provided for @colorScheme.
  ///
  /// In en, this message translates to:
  /// **'Color scheme'**
  String get colorScheme;

  /// No description provided for @themeBlue.
  ///
  /// In en, this message translates to:
  /// **'Default blue'**
  String get themeBlue;

  /// No description provided for @themeRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get themeRed;

  /// No description provided for @themeGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get themeGreen;

  /// No description provided for @themeTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get themeTeal;

  /// No description provided for @themeIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get themeIndigo;

  /// No description provided for @themeViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get themeViolet;

  /// No description provided for @themePink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get themePink;

  /// No description provided for @themeYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get themeYellow;

  /// No description provided for @themeOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get themeOrange;

  /// No description provided for @customSeedColor.
  ///
  /// In en, this message translates to:
  /// **'Custom seed color'**
  String get customSeedColor;

  /// No description provided for @seedColorHex.
  ///
  /// In en, this message translates to:
  /// **'Seed color (#RRGGBB)'**
  String get seedColorHex;

  /// No description provided for @seedColorHexError.
  ///
  /// In en, this message translates to:
  /// **'Enter #RRGGBB (six hexadecimal digits, no alpha).'**
  String get seedColorHexError;

  /// No description provided for @colorChannelRed.
  ///
  /// In en, this message translates to:
  /// **'Red channel'**
  String get colorChannelRed;

  /// No description provided for @colorChannelGreen.
  ///
  /// In en, this message translates to:
  /// **'Green channel'**
  String get colorChannelGreen;

  /// No description provided for @colorChannelBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue channel'**
  String get colorChannelBlue;

  /// No description provided for @applyColor.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyColor;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get followSystem;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @logBufferSize.
  ///
  /// In en, this message translates to:
  /// **'Log Buffer Size'**
  String get logBufferSize;

  /// No description provided for @logBufferSizeError.
  ///
  /// In en, this message translates to:
  /// **'16-512'**
  String get logBufferSizeError;

  /// No description provided for @enableAnsi.
  ///
  /// In en, this message translates to:
  /// **'Enable ANSI'**
  String get enableAnsi;

  /// No description provided for @autoSend.
  ///
  /// In en, this message translates to:
  /// **'Auto Send'**
  String get autoSend;

  /// No description provided for @secondsUnit.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get secondsUnit;

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export Logs'**
  String get exportLogs;

  /// No description provided for @exportPath.
  ///
  /// In en, this message translates to:
  /// **'Export path'**
  String get exportPath;

  /// No description provided for @exportPathHint.
  ///
  /// In en, this message translates to:
  /// **'Default folder for exported logs'**
  String get exportPathHint;

  /// No description provided for @logsExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Logs exported to: '**
  String get logsExportedTo;

  /// Export failure with a localized reason.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {message}'**
  String exportFailed(String message);

  /// No description provided for @writeFailure.
  ///
  /// In en, this message translates to:
  /// **'Write failed after {bytes} bytes: {message}'**
  String writeFailure(int bytes, String message);

  /// No description provided for @autoSendPaused.
  ///
  /// In en, this message translates to:
  /// **'Auto-send paused: {message}'**
  String autoSendPaused(String message);

  /// No description provided for @applyingConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Applying configuration...'**
  String get applyingConfiguration;

  /// No description provided for @logDataGap.
  ///
  /// In en, this message translates to:
  /// **'Some log events were missed; the view has been resynchronized.'**
  String get logDataGap;

  /// No description provided for @logTrimmed.
  ///
  /// In en, this message translates to:
  /// **'Older records trimmed: {records} records / {bytes} bytes'**
  String logTrimmed(int records, int bytes);

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'SkyPort could not start'**
  String get startupFailed;

  /// No description provided for @errorInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'Invalid argument'**
  String get errorInvalidArgument;

  /// No description provided for @errorPortNotFound.
  ///
  /// In en, this message translates to:
  /// **'Port not found'**
  String get errorPortNotFound;

  /// No description provided for @errorOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Port open failed'**
  String get errorOpenFailed;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errorPermissionDenied;

  /// No description provided for @errorUnsupportedConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Unsupported configuration'**
  String get errorUnsupportedConfiguration;

  /// No description provided for @errorReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Serial read failed'**
  String get errorReadFailed;

  /// No description provided for @errorDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Serial connection lost'**
  String get errorDisconnected;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Operation timed out'**
  String get errorTimeout;

  /// No description provided for @errorClosed.
  ///
  /// In en, this message translates to:
  /// **'Application core is closed'**
  String get errorClosed;

  /// No description provided for @errorQueueOverflow.
  ///
  /// In en, this message translates to:
  /// **'Queue capacity exceeded'**
  String get errorQueueOverflow;

  /// No description provided for @errorTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Background task failed'**
  String get errorTaskFailed;

  /// No description provided for @errorInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal error'**
  String get errorInternal;

  /// No description provided for @logIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The retained log contains a serial data or session gap.'**
  String get logIncomplete;

  /// No description provided for @diagnosticDetails.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic details'**
  String get diagnosticDetails;

  /// No description provided for @errorWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Serial write failed'**
  String get errorWriteFailed;

  /// No description provided for @errorPortNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a serial port.'**
  String get errorPortNameRequired;

  /// No description provided for @errorPortNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'The port name must not exceed 4096 bytes.'**
  String get errorPortNameTooLong;

  /// No description provided for @errorPortNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'The port name must not contain NUL or line breaks.'**
  String get errorPortNameInvalid;

  /// No description provided for @errorBaudRateInvalid.
  ///
  /// In en, this message translates to:
  /// **'The baud rate must be greater than zero.'**
  String get errorBaudRateInvalid;

  /// No description provided for @errorDataBitsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Data bits must be between 5 and 8.'**
  String get errorDataBitsInvalid;

  /// No description provided for @errorStopBitsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Stop bits must be 1 or 2.'**
  String get errorStopBitsInvalid;

  /// No description provided for @errorLegacyConfigInvalid.
  ///
  /// In en, this message translates to:
  /// **'The previous application\'s serial settings are invalid.'**
  String get errorLegacyConfigInvalid;

  /// No description provided for @errorConfigVersionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This configuration version is not supported.'**
  String get errorConfigVersionUnsupported;

  /// No description provided for @errorNewlineInvalid.
  ///
  /// In en, this message translates to:
  /// **'The stored newline must be LF, CR, or CRLF.'**
  String get errorNewlineInvalid;

  /// No description provided for @errorAutoSendIntervalInvalid.
  ///
  /// In en, this message translates to:
  /// **'The auto-send interval must be between 0.01 and 60 seconds.'**
  String get errorAutoSendIntervalInvalid;

  /// No description provided for @errorLogCapacityInvalid.
  ///
  /// In en, this message translates to:
  /// **'The log buffer size must be between 16 and 512 MiB.'**
  String get errorLogCapacityInvalid;

  /// No description provided for @errorHistoryTooLong.
  ///
  /// In en, this message translates to:
  /// **'Send history must not exceed 100 entries.'**
  String get errorHistoryTooLong;

  /// No description provided for @errorHistoryEntryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Send history must not contain empty entries.'**
  String get errorHistoryEntryEmpty;

  /// No description provided for @errorHistoryTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Send history must not exceed 1 MiB.'**
  String get errorHistoryTooLarge;

  /// No description provided for @errorConfigTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The configuration file must not exceed 8 MiB.'**
  String get errorConfigTooLarge;

  /// No description provided for @errorConfigInvalid.
  ///
  /// In en, this message translates to:
  /// **'The configuration file is invalid.'**
  String get errorConfigInvalid;

  /// No description provided for @errorConfigIo.
  ///
  /// In en, this message translates to:
  /// **'The configuration file could not be read or saved.'**
  String get errorConfigIo;

  /// No description provided for @errorSendTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Each transmission must not exceed 1 MiB.'**
  String get errorSendTooLarge;

  /// No description provided for @errorSendInputTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Send input must not exceed 2 MiB.'**
  String get errorSendInputTooLarge;

  /// No description provided for @errorAutoSendTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Auto-send data must not exceed 1 MiB.'**
  String get errorAutoSendTooLarge;

  /// No description provided for @errorSendEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter data to send.'**
  String get errorSendEmpty;

  /// No description provided for @errorNoLogsToExport.
  ///
  /// In en, this message translates to:
  /// **'No retained log records match the export options.'**
  String get errorNoLogsToExport;

  /// No description provided for @errorExportLog.
  ///
  /// In en, this message translates to:
  /// **'The log file could not be written.'**
  String get errorExportLog;

  /// No description provided for @errorQueueCapacityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Queue capacities must be between 1 and 4096.'**
  String get errorQueueCapacityInvalid;

  /// No description provided for @errorBridgeInitialization.
  ///
  /// In en, this message translates to:
  /// **'The serial core component could not be loaded. Check that the application installation is complete.'**
  String get errorBridgeInitialization;

  /// No description provided for @errorPreferenceMigration.
  ///
  /// In en, this message translates to:
  /// **'The migration status of the previous settings could not be saved.'**
  String get errorPreferenceMigration;

  /// No description provided for @errorPreferencesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The application settings could not be loaded.'**
  String get errorPreferencesUnavailable;

  /// No description provided for @errorFileAccess.
  ///
  /// In en, this message translates to:
  /// **'A required file or folder could not be accessed.'**
  String get errorFileAccess;

  /// No description provided for @errorPluginUnavailable.
  ///
  /// In en, this message translates to:
  /// **'A required platform service is unavailable.'**
  String get errorPluginUnavailable;

  /// No description provided for @errorPlatform.
  ///
  /// In en, this message translates to:
  /// **'A system service call failed.'**
  String get errorPlatform;

  /// No description provided for @errorPlatformUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This platform is not supported.'**
  String get errorPlatformUnsupported;

  /// No description provided for @errorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. See diagnostic details.'**
  String get errorUnexpected;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
