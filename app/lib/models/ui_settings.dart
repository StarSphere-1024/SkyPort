class UiSettings {
  final bool hexDisplay;
  final bool showTimestamp;
  final bool showSent;
  final bool enableAnsi;
  final String logExportPath;
  final bool autoCheckUpdates;

  const UiSettings({
    this.hexDisplay = false,
    this.showTimestamp = true,
    this.showSent = true,
    this.enableAnsi = false,
    this.logExportPath = '',
    this.autoCheckUpdates = true,
  });

  UiSettings copyWith({
    bool? hexDisplay,
    bool? showTimestamp,
    bool? showSent,
    bool? enableAnsi,
    String? logExportPath,
    bool? autoCheckUpdates,
  }) => UiSettings(
    hexDisplay: hexDisplay ?? this.hexDisplay,
    showTimestamp: showTimestamp ?? this.showTimestamp,
    showSent: showSent ?? this.showSent,
    enableAnsi: enableAnsi ?? this.enableAnsi,
    logExportPath: logExportPath ?? this.logExportPath,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
  );
}
