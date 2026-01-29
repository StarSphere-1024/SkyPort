import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/models/log_model.dart';

/// Test data constants and helpers
///
/// This file provides reusable test data for unit tests.
/// It includes sample configurations, data packets, and helper functions
/// to generate test data.

// Serial Config Tests
const String testPortName = 'COM1';
const int testBaudRate = 9600;
const int testDataBits = 8;
const int testParity = SerialPortParity.none;
const int testStopBits = 1;
const bool testAutoReconnect = true;

/// Serial config with default values
SerialConfig defaultSerialConfig() {
  return SerialConfig(
    portName: testPortName,
    baudRate: testBaudRate,
    dataBits: testDataBits,
    parity: testParity,
    stopBits: testStopBits,
    autoReconnect: testAutoReconnect,
  );
}

/// Serial config with custom baud rate
SerialConfig serialConfigWithBaudRate(int baudRate) {
  return SerialConfig(
    portName: testPortName,
    baudRate: baudRate,
    dataBits: testDataBits,
    parity: testParity,
    stopBits: testStopBits,
    autoReconnect: testAutoReconnect,
  );
}

/// Serial config with custom port name
SerialConfig serialConfigWithPort(String portName) {
  return SerialConfig(
    portName: portName,
    baudRate: testBaudRate,
    dataBits: testDataBits,
    parity: testParity,
    stopBits: testStopBits,
    autoReconnect: testAutoReconnect,
  );
}

// UI Settings Tests
const bool testHexDisplay = false;
const bool testHexSend = false;
const bool testShowTimestamp = true;
const bool testShowSent = true;
const int testBlockIntervalMs = 20;
const ReceiveMode testReceiveMode = ReceiveMode.block;
const ReceiveMode testPreferredReceiveMode = ReceiveMode.line;
const bool testAppendNewline = false;
const NewlineMode testNewlineMode = NewlineMode.lf;
const bool testEnableAnsi = false;
const int testLogBufferSize = 128;
const bool testAutoSendEnabled = false;
const int testAutoSendIntervalMs = 1000;

/// UI settings with default values
const UiSettings defaultUiSettings = UiSettings();

/// UI settings with hex display enabled
const UiSettings hexDisplaySettings = UiSettings(
  hexDisplay: true,
  hexSend: true,
  showTimestamp: false,
  showSent: true,
  blockIntervalMs: 20,
  receiveMode: ReceiveMode.block,
  preferredReceiveMode: ReceiveMode.line,
  appendNewline: false,
  newlineMode: NewlineMode.lf,
  enableAnsi: false,
  logBufferSize: 128,
  autoSendEnabled: false,
  autoSendIntervalMs: 1000,
);

/// UI settings with ANSI enabled
const UiSettings ansiEnabledSettings = UiSettings(
  hexDisplay: false,
  hexSend: false,
  showTimestamp: true,
  showSent: true,
  blockIntervalMs: 20,
  receiveMode: ReceiveMode.block,
  preferredReceiveMode: ReceiveMode.line,
  appendNewline: false,
  newlineMode: NewlineMode.lf,
  enableAnsi: true,
  logBufferSize: 128,
  autoSendEnabled: false,
  autoSendIntervalMs: 1000,
);

// Data Packets for Testing

/// ASCII "Hello" as bytes
Uint8List asciiHello() {
  return Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]); // "Hello"
}

/// ASCII "Hello World" with newline
Uint8List asciiHelloWithNewline() {
  return Uint8List.fromList([
    0x48, 0x65, 0x6C, 0x6C, 0x6F, // "Hello"
    0x20, // " "
    0x57, 0x6F, 0x72, 0x6C, 0x64, // "World"
    0x0A, // "\n"
  ]);
}

/// ANSI escape sequence for red text "Hello"
Uint8List ansiRedText() {
  return Uint8List.fromList([
    0x1B, 0x5B, 0x33, 0x31, 0x6D, // ESC[31m (red)
    0x48, 0x65, 0x6C, 0x6C, 0x6F, // "Hello"
    0x1B, 0x5B, 0x30, 0x6D, // ESC[0m (reset)
  ]);
}

/// ANSI escape sequence for bold green text
Uint8List ansiBoldGreenText() {
  return Uint8List.fromList([
    0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x32, 0x6D, // ESC[1;32m (bold green)
    0x53, 0x75, 0x63, 0x63, 0x65, 0x73, 0x73, // "Success"
    0x1B, 0x5B, 0x30, 0x6D, // ESC[0m (reset)
  ]);
}

/// Mixed newline sequences: \n, \r\n, \r
Uint8List mixedNewlines() {
  return Uint8List.fromList([
    0x4C, 0x69, 0x6E, 0x65, 0x31, 0x0A, // "Line1\n"
    0x4C, 0x69, 0x6E, 0x65, 0x32, 0x0D, 0x0A, // "Line2\r\n"
    0x4C, 0x69, 0x6E, 0x65, 0x33, 0x0D, // "Line3\r"
  ]);
}

/// CRLF sequence "\r\n"
Uint8List crlfSequence() {
  return Uint8List.fromList([0x0D, 0x0A]);
}

/// Multiple consecutive CRLFs
Uint8List multipleCrlfs() {
  return Uint8List.fromList([
    0x0D, 0x0A,
    0x0D, 0x0A,
    0x0D, 0x0A,
  ]);
}

/// Empty packet
Uint8List emptyPacket() {
  return Uint8List(0);
}

/// Single byte packet
Uint8List singleByte() {
  return Uint8List.fromList([0x42]); // "B"
}

/// Large packet (1KB)
Uint8List largePacket1kb() {
  return Uint8List(1024);
}

/// Very large packet (256KB - pending buffer limit)
Uint8List veryLargePacket256kb() {
  return Uint8List(256 * 1024);
}

/// Packet exceeding pending buffer limit (300KB)
Uint8List exceedingPendingBuffer() {
  return Uint8List(300 * 1024);
}

/// Binary data with all byte values 0x00-0xFF
Uint8List allByteValues() {
  return Uint8List.fromList(List.generate(256, (i) => i));
}

/// Hex string representation
String hexStringHello() => '48 65 6C 6C 6F';

/// Invalid hex string
String invalidHexString() => '48 65 2G 6C 6F'; // 2G is invalid

/// Hex string with odd length (will be padded)
String oddLengthHexString() => '48 65 6C 6C'; // Missing last byte

/// Hex string with whitespace
String hexStringWithWhitespace() => '48 65  6C   6C 6F';

/// Creates a LogEntry for testing
LogEntry createTestLogEntry(Uint8List data, LogEntryType type) {
  return LogEntry(data, type, DateTime.now());
}

/// Creates a received LogEntry
LogEntry createReceivedLogEntry(Uint8List data) {
  return LogEntry(data, LogEntryType.received, DateTime.now());
}

/// Creates a sent LogEntry
LogEntry createSentLogEntry(Uint8List data) {
  return LogEntry(data, LogEntryType.sent, DateTime.now());
}

/// Creates multiple LogEntry objects
List<LogEntry> createMultipleLogEntries(int count) {
  final now = DateTime.now();
  return List.generate(count, (i) {
    final data = Uint8List.fromList('Message $i\n'.codeUnits);
    return LogEntry(data, LogEntryType.received, now.add(Duration(milliseconds: i)));
  });
}

/// Test port names
const List<String> testPortNames = [
  'COM1',
  'COM2',
  'COM3',
  '/dev/ttyUSB0',
  '/dev/ttyUSB1',
  '/dev/tty.usbserial',
];

/// Common baud rates for testing
const List<int> testBaudRates = [
  9600,
  19200,
  38400,
  57600,
  115200,
  230400,
  460800,
  921600,
];

/// Invalid port names for error testing
const List<String> invalidPortNames = [
  '',
  'INVALID',
  'COM9999',
  '/dev/nonexistent',
];

/// UTF-8 test strings
const String utf8English = 'Hello World';
const String utf8Chinese = '你好世界';
const String utf8Emoji = '🎉🚀✨';
const String utf8Mixed = 'Hello 你好 🎉';

/// Invalid UTF-8 sequence
Uint8List invalidUtf8() {
  // Invalid UTF-8: continuation byte without start byte
  return Uint8List.fromList([0x80, 0x81, 0x82]);
}

/// ANSI color codes for testing
const String ansiRed = '\x1b[31m';
const String ansiGreen = '\x1b[32m';
const String ansiYellow = '\x1b[33m';
const String ansiBlue = '\x1b[34m';
const String ansiMagenta = '\x1b[35m';
const String ansiCyan = '\x1b[36m';
const String ansiWhite = '\x1b[37m';
const String ansiReset = '\x1b[0m';
const String ansiBold = '\x1b[1m';

/// ANSI styled text samples - helper functions to create styled strings
String ansiStyledRed(String text) => '$ansiRed$text$ansiReset';
String ansiStyledGreen(String text) => '$ansiGreen$text$ansiReset';
String ansiStyledBold(String text) => '$ansiBold$text$ansiReset';
String ansiStyledBoldRed(String text) => '$ansiBold$ansiRed$text$ansiReset';
