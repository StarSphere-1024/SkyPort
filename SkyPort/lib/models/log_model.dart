import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

enum LogEntryType { received, sent }

class LogEntry {
  final Uint8List data;
  final LogEntryType type;
  final DateTime timestamp;
  String? _cachedText;
  bool? _cachedHexMode;

  // Static LRU Cache for rendered TextSpans
  // Limits memory usage by only keeping the most recently rendered spans (e.g. visible items)
  static const int _maxCacheSize = 500;
  static final LinkedHashMap<LogEntry, _CachedSpanData> _spanCache =
      LinkedHashMap<LogEntry, _CachedSpanData>();

  LogEntry(this.data, this.type, this.timestamp);

  String getDisplayText(bool hexDisplay) {
    if (_cachedText != null && _cachedHexMode == hexDisplay) {
      return _cachedText!;
    }

    if (hexDisplay) {
      _cachedText = data
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    } else {
      _cachedText = utf8.decode(data, allowMalformed: true);
    }
    _cachedHexMode = hexDisplay;
    return _cachedText!;
  }

  List<InlineSpan> getSpans({
    required bool hexDisplay,
    required bool showTimestamp,
    required bool showSent,
    required bool enableAnsi,
    required TextStyle baseStyle,
    required TextStyle timestampStyle,
    required Color primaryColor,
    required Color onSurfaceColor,
  }) {
    final key = Object.hash(
      hexDisplay,
      showTimestamp,
      showSent,
      enableAnsi,
      baseStyle,
      timestampStyle,
      primaryColor,
      onSurfaceColor,
    );

    // 1. Check LRU Cache
    if (_spanCache.containsKey(this)) {
      final cachedData = _spanCache[this]!;
      if (cachedData.settingsHash == key) {
        // Cache Hit: Move to end (MRU) and return
        _spanCache.remove(this);
        _spanCache[this] = cachedData;
        return cachedData.spans;
      }
    }

    // 2. Generate
    final spans = _generateSpans(
      hexDisplay,
      showTimestamp,
      showSent,
      enableAnsi,
      baseStyle,
      timestampStyle,
      primaryColor,
      onSurfaceColor,
    );

    // 3. Update LRU Cache
    if (_spanCache.length >= _maxCacheSize) {
      _spanCache.remove(_spanCache.keys.first); // Remove LRU (first)
    }
    _spanCache[this] = _CachedSpanData(key, spans); // Add to MRU (end)

    return spans;
  }

  List<InlineSpan> _generateSpans(
    bool hexDisplay,
    bool showTimestamp,
    bool showSent,
    bool enableAnsi,
    TextStyle baseStyle,
    TextStyle timestampStyle,
    Color primaryColor,
    Color onSurfaceColor,
  ) {
    final isSent = type == LogEntryType.sent;
    final formattedTimestamp = DateFormat('HH:mm:ss.SSS').format(timestamp);
    final dataText = getDisplayText(hexDisplay);
    final lines = dataText.split('\n');
    final spans = <InlineSpan>[];

    for (int j = 0; j < lines.length; j++) {
      final lineText = lines[j];

      if (j == 0 && showTimestamp) {
        spans.add(
          TextSpan(
            text: '$formattedTimestamp ',
            style: timestampStyle,
          ),
        );
      }

      if (j == 0 && showSent) {
        spans.add(TextSpan(
          text: isSent ? 'TX > ' : 'RX < ',
          style: baseStyle.copyWith(
            color: isSent ? primaryColor : onSurfaceColor,
            fontWeight: FontWeight.bold,
          ),
        ));
      }

      final contentColor =
          isSent ? primaryColor.withValues(alpha: 0.8) : onSurfaceColor;

      final contentStyle = baseStyle.copyWith(color: contentColor);

      if (enableAnsi) {
        final parser = ansi.AnsiParser(lineText);
        for (final match in parser.matches) {
          final text = lineText.substring(match.start, match.end);
          if (text.startsWith('\x1b')) continue;

          spans.add(TextSpan(
            text: text,
            style: _ansiStateToStyle(match.state, contentStyle),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: lineText,
          style: contentStyle,
        ));
      }

      // Handle newlines
      if (j < lines.length - 1) {
        // Check if this is a trailing newline (data ends with \n)
        final isTrailingNewline = (j == lines.length - 2 && lines.last.isEmpty);
        // Check if the current line is empty (caused by consecutive \n like \n\n)
        final isInternalEmptyLine = lineText.isEmpty;

        if (isTrailingNewline || isInternalEmptyLine) {
          // Use a zero-sized WidgetSpan for trailing newlines OR internal empty lines.
          // This creates a "compact" view where empty lines don't take up visual space
          // but are still present when copied to clipboard.
          spans.add(WidgetSpan(
            child: SizedBox(
              width: 0,
              height: 0,
              child: Text(
                '\n',
                style: contentStyle.copyWith(fontSize: 1),
              ),
            ),
          ));
        } else {
          // Normal internal newline after text, render as visible text to break the line
          spans.add(TextSpan(
            text: '\n',
            style: contentStyle,
          ));
        }
      }
    }
    return spans;
  }

  static TextStyle _ansiStateToStyle(dynamic state, TextStyle baseStyle) {
    Color? fg;
    Color? bg;
    bool bold = false;
    bool italic = false;
    bool underline = false;

    Color? getFlutterColor(dynamic ansiColorObject) {
      if (ansiColorObject == null) return null;
      try {
        final runtimeTypeStr = ansiColorObject.runtimeType.toString();
        if (runtimeTypeStr.contains('Color16')) {
          final dynamic colorEnum = ansiColorObject.color;
          final int index = colorEnum.index as int;
          switch (index) {
            case 0:
              return Colors.black;
            case 1:
              return Colors.red;
            case 2:
              return Colors.green;
            case 3:
              return Colors.yellow;
            case 4:
              return Colors.blue;
            case 5:
              return Colors.purple;
            case 6:
              return Colors.cyan;
            case 7:
              return Colors.white70;
            case 8:
              return Colors.grey;
            case 9:
              return Colors.redAccent;
            case 10:
              return Colors.greenAccent;
            case 11:
              return Colors.yellowAccent;
            case 12:
              return Colors.blueAccent;
            case 13:
              return Colors.purpleAccent;
            case 14:
              return Colors.cyanAccent;
            case 15:
              return Colors.white;
            default:
              return null;
          }
        }
      } catch (e) {
        // Ignore exceptions when accessing ANSI color properties
      }
      return null;
    }

    try {
      if (state != null) {
        fg = getFlutterColor(state.foreground);
        bg = getFlutterColor(state.background);
        try {
          if (state.isBold == true) bold = true;
        } catch (_) {}
        try {
          if (state.isItalicized == true) italic = true;
        } catch (_) {}
        try {
          if (state.isSinglyUnderlined == true) underline = true;
        } catch (_) {}
      }
    } catch (e) {
      // Ignore exceptions when accessing ANSI state properties
    }

    return baseStyle.copyWith(
      color: fg,
      backgroundColor: bg,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline ? TextDecoration.underline : null,
    );
  }
}

class _CachedSpanData {
  final int settingsHash;
  final List<InlineSpan> spans;
  _CachedSpanData(this.settingsHash, this.spans);
}

class LogChunk {
  final List<LogEntry> entries;
  final int totalBytes;
  final int id;

  List<LogEntry>? _rxEntries;
  List<LogEntry> get rxEntries => _rxEntries ??=
      entries.where((e) => e.type == LogEntryType.received).toList();

  LogChunk({required this.entries, required this.totalBytes, required this.id});
}

class LogState {
  final List<LogChunk> chunks;
  final int totalBytes;
  final int nextChunkId;

  const LogState({
    this.chunks = const [],
    this.totalBytes = 0,
    this.nextChunkId = 0,
  });

  List<LogEntry> get allEntries => chunks.expand((c) => c.entries).toList();
}
