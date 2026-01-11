/// Mode for which newline sequence to append when sending text data.
enum NewlineMode {
  lf, // "\n"
  cr, // "\r"
  crlf, // "\r\n"
}

/// Receive mode for data reception.
enum ReceiveMode {
  line,
  block,
}

class UiSettings {
  final bool hexDisplay;
  final bool hexSend;
  final bool showTimestamp;
  final bool showSent; // Whether to display sent data in the log
  final int
      blockIntervalMs; // Block interval in milliseconds for block receive mode
  final ReceiveMode receiveMode; // Receive mode: line or block
  final ReceiveMode
      preferredReceiveMode; // User's preferred receive mode in text mode
  // Sending new line settings
  final bool appendNewline; // Whether to append a newline when sending text
  final NewlineMode newlineMode; // Which newline sequence to append
  final bool enableAnsi; // Whether to enable ANSI escape sequence rendering
  final int logBufferSize; // Log buffer size in MB

  const UiSettings({
    this.hexDisplay = false,
    this.hexSend = false,
    this.showTimestamp = true,
    this.showSent = true,
    this.blockIntervalMs = 20,
    this.receiveMode = ReceiveMode.block, // Default to block receive mode
    this.preferredReceiveMode =
        ReceiveMode.line, // Default to line receive mode in text mode
    this.appendNewline = false,
    this.newlineMode = NewlineMode.lf,
    this.enableAnsi = false,
    this.logBufferSize = 128, // Default 128 MB
  });

  UiSettings copyWith({
    bool? hexDisplay,
    bool? hexSend,
    bool? showTimestamp,
    bool? showSent,
    int? blockIntervalMs,
    ReceiveMode? receiveMode,
    ReceiveMode? preferredReceiveMode,
    bool? appendNewline,
    NewlineMode? newlineMode,
    bool? enableAnsi,
    int? logBufferSize,
  }) {
    return UiSettings(
      hexDisplay: hexDisplay ?? this.hexDisplay,
      hexSend: hexSend ?? this.hexSend,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showSent: showSent ?? this.showSent,
      blockIntervalMs: blockIntervalMs ?? this.blockIntervalMs,
      receiveMode: receiveMode ?? this.receiveMode,
      preferredReceiveMode: preferredReceiveMode ?? this.preferredReceiveMode,
      appendNewline: appendNewline ?? this.appendNewline,
      newlineMode: newlineMode ?? this.newlineMode,
      enableAnsi: enableAnsi ?? this.enableAnsi,
      logBufferSize: logBufferSize ?? this.logBufferSize,
    );
  }
}
