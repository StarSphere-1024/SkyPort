/// Mode for which newline sequence to append when sending text data.
enum NewlineMode {
  lf, // "\n"
  cr, // "\r"
  crlf, // "\r\n"
}

class UiSettings {
  final bool hexDisplay;
  final bool hexSend;
  final bool showTimestamp;
  final bool showSent; // Whether to display sent data in the log
  // Sending new line settings
  final bool appendNewline; // Whether to append a newline when sending text
  final NewlineMode newlineMode; // Which newline sequence to append
  final bool enableAnsi; // Whether to enable ANSI escape sequence rendering
  final int logBufferSize; // Log buffer size in MB
  final bool autoSendEnabled; // Whether auto-send is enabled
  final int autoSendIntervalMs; // Auto-send interval in milliseconds

  const UiSettings({
    this.hexDisplay = false,
    this.hexSend = false,
    this.showTimestamp = true,
    this.showSent = true,
    this.appendNewline = false,
    this.newlineMode = NewlineMode.lf,
    this.enableAnsi = false,
    this.logBufferSize = 128, // Default 128 MB
    this.autoSendEnabled = false,
    this.autoSendIntervalMs = 1000, // Default 1000ms (1 second)
  });

  UiSettings copyWith({
    bool? hexDisplay,
    bool? hexSend,
    bool? showTimestamp,
    bool? showSent,
    bool? appendNewline,
    NewlineMode? newlineMode,
    bool? enableAnsi,
    int? logBufferSize,
    bool? autoSendEnabled,
    int? autoSendIntervalMs,
  }) {
    return UiSettings(
      hexDisplay: hexDisplay ?? this.hexDisplay,
      hexSend: hexSend ?? this.hexSend,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showSent: showSent ?? this.showSent,
      appendNewline: appendNewline ?? this.appendNewline,
      newlineMode: newlineMode ?? this.newlineMode,
      enableAnsi: enableAnsi ?? this.enableAnsi,
      logBufferSize: logBufferSize ?? this.logBufferSize,
      autoSendEnabled: autoSendEnabled ?? this.autoSendEnabled,
      autoSendIntervalMs: autoSendIntervalMs ?? this.autoSendIntervalMs,
    );
  }
}
