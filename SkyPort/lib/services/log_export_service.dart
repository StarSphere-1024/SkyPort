import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

import '../models/log_model.dart';
import '../l10n/app_localizations.dart';

/// Service class for exporting log entries to file
/// WYSIWYG: Export content matches exactly what user sees in UI
class LogExportService {
  /// Export logs to file with user-selected path
  /// Export content matches current UI display (WYSIWYG)
  ///
  /// Returns the export path if succeeded, null if cancelled or failed
  static Future<String?> exportLogs({
    required BuildContext context,
    required List<LogChunk> chunks,
    required bool showSent,
    required bool hexDisplay,
    required bool showTimestamp,
    required bool enableAnsi,
    required String defaultPath,
    required String portName,
  }) async {
    // 1. Filter entries based on showSent setting (match UI display)
    final entries = _filterEntries(chunks, showSent);

    if (entries.isEmpty) {
      if (context.mounted) {
        _showMessage(context, 'noLogsToExport');
      }
      return null;
    }

    // 2. Generate filename: COM3_20260312.txt
    final timestamp = _formatDate(DateTime.now());
    final safePortName = portName.isEmpty
        ? 'serial'
        : portName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final defaultFilename = '${safePortName}_$timestamp.txt';

    // 3. Generate WYSIWYG content - exactly what user sees
    final content = _generateWysiwygContent(
      entries,
      hexDisplay,
      showTimestamp,
      showSent,
      enableAnsi,
    );

    // 4. Let user pick save location and write content
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save log file',
      fileName: defaultFilename,
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: defaultPath.isNotEmpty ? defaultPath : null,
      bytes: utf8.encode(content),
    );

    if (result == null) return null; // User cancelled or web download

    try {
      if (context.mounted) {
        _showMessage(context, 'logsExportedTo', extra: result);
      }
      return result;
    } catch (e) {
      if (context.mounted) {
        _showMessage(context, 'exportFailed', extra: e.toString());
      }
      return null;
    }
  }

  /// Filter entries based on showSent setting (match UI display)
  /// Package-visible for testing
  @visibleForTesting
  static List<LogEntry> filterEntriesForTest(
    List<LogChunk> chunks,
    bool showSent,
  ) {
    return _filterEntries(chunks, showSent);
  }

  static List<LogEntry> _filterEntries(
    List<LogChunk> chunks,
    bool showSent,
  ) {
    // Return entries matching current UI display setting
    return showSent
        ? chunks.expand((c) => c.entries).toList()
        : chunks.expand((c) => c.rxEntries).toList();
  }

  /// Generate WYSIWYG export content - exactly matches UI display
  /// Includes: timestamp, TX/RX markers, rendered data text, ANSI parsing
  /// Package-visible for testing
  @visibleForTesting
  static String generateWysiwygContentForTest(
    List<LogEntry> entries,
    bool hexDisplay,
    bool showTimestamp,
    bool showSent,
    bool enableAnsi,
  ) {
    return _generateWysiwygContent(
        entries, hexDisplay, showTimestamp, showSent, enableAnsi);
  }

  static String _generateWysiwygContent(
    List<LogEntry> entries,
    bool hexDisplay,
    bool showTimestamp,
    bool showSent,
    bool enableAnsi,
  ) {
    final buffer = StringBuffer();

    for (final entry in entries) {
      final isSent = entry.type == LogEntryType.sent;
      final formattedTimestamp =
          DateFormat('HH:mm:ss.SSS').format(entry.timestamp);
      final displayText = entry.getDisplayTextPreview(hexDisplay);
      final dataText = displayText.text;

      // Truncation (same as UI)
      final truncated = displayText.truncated;

      final lines = dataText.split('\n');

      for (int j = 0; j < lines.length; j++) {
        final line = lines[j];

        // Build line content
        final lineBuffer = StringBuffer();

        // Timestamp (if enabled)
        if (j == 0 && showTimestamp) {
          lineBuffer.write('$formattedTimestamp ');
        }

        // TX/RX marker (if enabled)
        if (j == 0 && showSent) {
          lineBuffer.write(isSent ? 'TX > ' : 'RX < ');
        }

        // Data content
        if (enableAnsi && !hexDisplay) {
          lineBuffer.write(ansi.Parser(line).removeAll());
        } else {
          lineBuffer.write(line);
        }

        // Truncation indicator
        if (truncated && j == lines.length - 1) {
          lineBuffer.write(' ... [TRUNCATED]');
        }

        // Newline handling (same as UI)
        if (j < lines.length - 1) {
          final isTrailingNewline =
              (j == lines.length - 2 && lines.last.isEmpty);
          final isInternalEmptyLine = line.isEmpty;
          if (isTrailingNewline || isInternalEmptyLine) {
            lineBuffer.write('\n');
          } else {
            lineBuffer.write('\n');
          }
        } else {
          lineBuffer.write('\n');
        }

        buffer.write(lineBuffer.toString());
      }
    }

    return buffer.toString();
  }

  /// Format date as YYYYMMDD
  /// Package-visible for testing
  @visibleForTesting
  static String formatDateForTest(DateTime dt) {
    return _formatDate(dt);
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// Show localized message using ScaffoldMessenger
  static void _showMessage(BuildContext context, String key, {String? extra}) {
    final l10n = AppLocalizations.of(context);
    final message = switch (key) {
      'noLogsToExport' => l10n.noLogsToExport,
      'logsExportedTo' => '${l10n.logsExportedTo}$extra',
      'exportFailed' => '${l10n.exportFailed}$extra',
      _ => key,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
