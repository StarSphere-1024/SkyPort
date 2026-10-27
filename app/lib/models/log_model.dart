import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

import '../utils/constants.dart';

enum LogEntryType { received, sent }

class LogEntry {
  final int id;
  final Uint8List data;
  final LogEntryType type;
  final DateTime timestamp;
  String? _cachedText;
  bool? _cachedHexMode;

  // Static LRU Cache for rendered TextSpans
  // Limits memory usage by only keeping the most recently rendered spans (e.g. visible items)
  static const int _maxCacheSize = SkyPortConstants.lruCacheMaxSize;
  static final LinkedHashMap<LogEntry, _CachedSpanData> _spanCache =
      LinkedHashMap<LogEntry, _CachedSpanData>();

  LogEntry(this.data, this.type, this.timestamp, {this.id = -1});

  String getDisplayText(bool hexDisplay) {
    if (_cachedText != null && _cachedHexMode == hexDisplay) {
      return _cachedText!;
    }

    if (hexDisplay) {
      // Hex mode with soft line breaks every 32 bytes
      final buffer = StringBuffer();
      for (int i = 0; i < data.length; i++) {
        // Convert to hex
        buffer.write(data[i].toRadixString(16).padLeft(2, '0').toUpperCase());
        buffer.write(' ');

        // Insert soft line break every 32 bytes to avoid extremely long lines
        if ((i + 1) % 32 == 0) {
          buffer.write('\n');
        }
      }
      _cachedText = buffer.toString();
    } else {
      _cachedText = utf8.decode(data, allowMalformed: true);
    }
    _cachedHexMode = hexDisplay;
    return _cachedText!;
  }

  bool get debugHasCachedDisplayText => _cachedText != null;

  void clearDisplayCache() {
    _cachedText = null;
    _cachedHexMode = null;
    _spanCache.remove(this);
  }

  static void evictCachedData(Iterable<LogEntry> entries) {
    for (final entry in entries) {
      entry.clearDisplayCache();
    }
  }

  static void clearSpanCache() {
    final cachedEntries = _spanCache.keys.toList();
    for (final entry in cachedEntries) {
      entry.clearDisplayCache();
    }
    _spanCache.clear();
  }

  ({String text, bool truncated}) getDisplayTextPreview(bool hexDisplay) {
    const maxLength = SkyPortConstants.logDisplayMaxLength;
    if (hexDisplay) {
      return _getHexDisplayPreview(maxLength);
    }
    if (data.length <= maxLength) {
      return (text: getDisplayText(false), truncated: false);
    }
    return (
      text: utf8.decode(
        Uint8List.sublistView(data, 0, maxLength),
        allowMalformed: true,
      ),
      truncated: true,
    );
  }

  ({String text, bool truncated}) _getHexDisplayPreview(int maxLength) {
    final buffer = StringBuffer();
    for (int i = 0; i < data.length; i++) {
      final token =
          '${data[i].toRadixString(16).padLeft(2, '0').toUpperCase()} ';
      final newline = (i + 1) % 32 == 0 ? '\n' : '';
      if (buffer.length + token.length + newline.length > maxLength) {
        return (text: buffer.toString(), truncated: true);
      }
      buffer.write(token);
      if (newline.isNotEmpty) {
        buffer.write(newline);
      }
    }
    return (text: buffer.toString(), truncated: false);
  }

  /// Search offsets are UTF-16, exactly like Dart String substring offsets.
  /// The bounded canonical view may be centered well beyond the normal preview.
  List<InlineSpan> getSearchSpans({
    required String text,
    required List<({int start, int end})> ranges,
    required ({int start, int end})? focus,
    required bool showTimestamp,
    required bool showSent,
    required TextStyle baseStyle,
    required TextStyle timestampStyle,
    required Color primaryColor,
    required Color onSurfaceColor,
    required Color matchColor,
    required Color selectedColor,
  }) {
    final sent = type == LogEntryType.sent;
    final style = baseStyle.copyWith(
      color: sent ? primaryColor : onSurfaceColor,
    );
    final spans = <InlineSpan>[
      if (showTimestamp)
        TextSpan(
          text: '${DateFormat('HH:mm:ss.SSS').format(timestamp)} ',
          style: timestampStyle,
        ),
      if (showSent)
        TextSpan(
          text: sent ? 'TX > ' : 'RX < ',
          style: style.copyWith(fontWeight: FontWeight.bold),
        ),
    ];
    void append(int start, int end, TextStyle spanStyle) {
      var cursor = start;
      while (cursor < end) {
        final newline = text.indexOf('\n', cursor);
        if (newline < 0 || newline >= end) {
          spans.add(
            TextSpan(text: text.substring(cursor, end), style: spanStyle),
          );
          break;
        }
        if (newline > cursor) {
          spans.add(
            TextSpan(text: text.substring(cursor, newline), style: spanStyle),
          );
        }
        // Use source offsets, not highlight boundaries, to classify blank lines.
        final compact =
            newline == text.length - 1 ||
            newline == 0 ||
            text.codeUnitAt(newline - 1) == 10;
        spans.add(
          compact
              ? _compactNewline(spanStyle)
              : TextSpan(text: '\n', style: spanStyle),
        );
        cursor = newline + 1;
      }
    }

    var cursor = 0;
    for (final range in ranges) {
      final start = range.start.clamp(cursor, text.length);
      final end = range.end.clamp(start, text.length);
      if (start > cursor) {
        append(cursor, start, style);
      }
      if (end > start) {
        final selected =
            focus != null && start < focus.end && end > focus.start;
        append(
          start,
          end,
          style.copyWith(
            backgroundColor: selected ? selectedColor : matchColor,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        );
      }
      cursor = end;
    }
    if (cursor < text.length) {
      append(cursor, text.length, style);
    }
    return spans;
  }

  static WidgetSpan _compactNewline(TextStyle style) => WidgetSpan(
    child: SizedBox(
      width: 0,
      height: 0,
      child: Text('\n', style: style.copyWith(fontSize: 1)),
    ),
  );

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
      _spanCache.keys.first.clearDisplayCache(); // Remove LRU (first)
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
    final formattedTimestamp = showTimestamp
        ? DateFormat('HH:mm:ss.SSS').format(timestamp)
        : '';
    final displayText = getDisplayTextPreview(hexDisplay);
    final dataText = displayText.text;

    // Truncation defense for both text and hex mode. Rendering must never
    // decode or allocate for the full payload when the visible output is capped.
    final truncated = displayText.truncated;
    final text = dataText;

    final lines = text.split('\n');
    final spans = <InlineSpan>[];

    for (int j = 0; j < lines.length; j++) {
      final lineText = lines[j];

      if (j == 0 && showTimestamp) {
        spans.add(
          TextSpan(text: '$formattedTimestamp ', style: timestampStyle),
        );
      }

      if (j == 0 && showSent) {
        spans.add(
          TextSpan(
            text: isSent ? 'TX > ' : 'RX < ',
            style: baseStyle.copyWith(
              color: isSent ? primaryColor : onSurfaceColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }

      final contentColor = isSent ? primaryColor : onSurfaceColor;

      final contentStyle = baseStyle.copyWith(color: contentColor);

      if (enableAnsi) {
        final parser = ansi.Parser(lineText);
        for (final piece in parser.pieces) {
          final textSegment = lineText.substring(piece.start, piece.end);
          if (piece.entity is ansi.EscapeCode) continue;

          spans.add(
            TextSpan(
              text: textSegment,
              style: _ansiStateToStyle(piece.state, contentStyle),
            ),
          );
        }
      } else {
        spans.add(TextSpan(text: lineText, style: contentStyle));
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
          spans.add(_compactNewline(contentStyle));
        } else {
          // Normal internal newline after text, render as visible text to break the line
          spans.add(TextSpan(text: '\n', style: contentStyle));
        }
      }
    }

    // Add truncation indicator if text was cut
    if (truncated) {
      spans.add(
        TextSpan(
          text: ' ... [TRUNCATED]',
          style: baseStyle.copyWith(
            color: onSurfaceColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
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
        fg = getFlutterColor(state.foregroundColor);
        bg = getFlutterColor(state.backgroundColor);
        try {
          if (state.isBold == true) bold = true;
        } catch (_) {}
        try {
          if (state.isItalic == true) italic = true;
        } catch (_) {}
        try {
          if (state.isUnderline == true) underline = true;
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
  final int id;

  List<LogEntry>? _rxEntries;
  List<LogEntry> get rxEntries => _rxEntries ??= entries
      .where((e) => e.type == LogEntryType.received)
      .toList();

  LogChunk({required this.entries, required this.id});

  // Core IDs increase by completion; the reserved pending ID is always last.
  static int insertionIndex(List<LogChunk> chunks, int id) {
    var low = 0;
    var high = chunks.length;
    if (high > 0 && chunks.last.id == 0xFFFFFFFFFFFFFFFF) high--;
    if (id == 0xFFFFFFFFFFFFFFFF) return high;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (chunks[mid].id < id) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

class LogState {
  final List<LogChunk> chunks;
  final int totalBytes;

  const LogState({this.chunks = const [], this.totalBytes = 0});
}
