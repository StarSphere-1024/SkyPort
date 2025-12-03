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
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SkyPort'**
  String get appTitle;

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

  /// No description provided for @loadingPorts.
  ///
  /// In en, this message translates to:
  /// **'Loading ports...'**
  String get loadingPorts;

  /// No description provided for @errorLoadingPorts.
  ///
  /// In en, this message translates to:
  /// **'Error loading ports'**
  String get errorLoadingPorts;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

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

  /// No description provided for @receiveMode.
  ///
  /// In en, this message translates to:
  /// **'Receive mode'**
  String get receiveMode;

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

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get loadMore;

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

  /// No description provided for @txLabel.
  ///
  /// In en, this message translates to:
  /// **'TX'**
  String get txLabel;

  /// No description provided for @rxLabel.
  ///
  /// In en, this message translates to:
  /// **'RX'**
  String get rxLabel;

  /// No description provided for @connectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Connected to {port}@{baud}'**
  String connectedStatus(String port, int baud);

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

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @trafficStats.
  ///
  /// In en, this message translates to:
  /// **'Rx: {rx} - {lastRx} | Tx: {tx}'**
  String trafficStats(int rx, int tx, int lastRx);

  /// No description provided for @trafficStatsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Total received bytes - Last packet size | Total sent bytes'**
  String get trafficStatsTooltip;

  /// No description provided for @timeoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Block Interval'**
  String get timeoutLabel;

  /// No description provided for @receiveModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Line: Split data when newline is received\nBlock: Split data when no data received for set time'**
  String get receiveModeTooltip;

  /// No description provided for @receiveModeTooltipHex.
  ///
  /// In en, this message translates to:
  /// **'Line mode not available in Hex display\nBlock: Split data when no data received for set time'**
  String get receiveModeTooltipHex;

  /// No description provided for @lineModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get lineModeLabel;

  /// No description provided for @blockModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockModeLabel;
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
      'that was used.');
}
