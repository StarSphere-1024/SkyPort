import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/services/log_export_service.dart';

// Mock BuildContext for testing
class MockBuildContext extends Mock implements BuildContext {}

void main() {
  group('LogExportService', () {
    group('_filterEntries', () {
      test('returns all entries when showSent=true', () {
        final now = DateTime.now();
        final chunk = LogChunk(
          entries: [
            LogEntry(Uint8List.fromList('RX1'.codeUnits), LogEntryType.received, now),
            LogEntry(Uint8List.fromList('TX1'.codeUnits), LogEntryType.sent, now),
          ],
          totalBytes: 6,
          id: 1,
        );

        final result = LogExportService.filterEntriesForTest([chunk], true);

        expect(result.length, 2);
        expect(result[0].type, LogEntryType.received);
        expect(result[1].type, LogEntryType.sent);
      });

      test('returns only RX entries when showSent=false', () {
        final now = DateTime.now();
        final chunk = LogChunk(
          entries: [
            LogEntry(Uint8List.fromList('RX1'.codeUnits), LogEntryType.received, now),
            LogEntry(Uint8List.fromList('TX1'.codeUnits), LogEntryType.sent, now),
            LogEntry(Uint8List.fromList('RX2'.codeUnits), LogEntryType.received, now),
          ],
          totalBytes: 9,
          id: 1,
        );

        final result = LogExportService.filterEntriesForTest([chunk], false);

        expect(result.length, 2);
        expect(result.every((e) => e.type == LogEntryType.received), true);
      });

      test('returns empty list when chunks is empty', () {
        final result = LogExportService.filterEntriesForTest([], true);
        expect(result.isEmpty, true);
      });

      test('handles multiple chunks', () {
        final now = DateTime.now();
        final chunk1 = LogChunk(
          entries: [
            LogEntry(Uint8List.fromList('RX1'.codeUnits), LogEntryType.received, now),
          ],
          totalBytes: 3,
          id: 1,
        );
        final chunk2 = LogChunk(
          entries: [
            LogEntry(Uint8List.fromList('TX1'.codeUnits), LogEntryType.sent, now),
          ],
          totalBytes: 3,
          id: 2,
        );

        final result = LogExportService.filterEntriesForTest([chunk1, chunk2], true);

        expect(result.length, 2);
      });
    });

    group('_formatDate', () {
      test('formats date as YYYYMMDD', () {
        final dt = DateTime(2026, 3, 13, 14, 30, 45);
        final result = LogExportService.formatDateForTest(dt);
        expect(result, '20260313');
      });

      test('pads single digit month and day', () {
        final dt = DateTime(2026, 1, 5, 14, 30, 45);
        final result = LogExportService.formatDateForTest(dt);
        expect(result, '20260105');
      });

      test('handles year boundary', () {
        final dt = DateTime(2025, 12, 31, 23, 59, 59);
        final result = LogExportService.formatDateForTest(dt);
        expect(result, '20251231');
      });
    });

    group('_generateWysiwygContent', () {
      group('Basic Cases', () {
        test('returns empty string for empty entries', () {
          final result = LogExportService.generateWysiwygContentForTest(
            [],
            false,
            true,
            true,
            false,
          );
          expect(result, '');
        });

        test('includes timestamp when showTimestamp=true', () {
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 123);
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.received,
            timestamp,
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            true,
            false,
            false,
          );

          expect(result.contains('14:30:45.123'), true);
        });

        test('excludes timestamp when showTimestamp=false', () {
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 123);
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.received,
            timestamp,
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result.contains('14:30:45'), false);
          expect(result, 'Hello\n');
        });

        test('includes TX marker for sent entries when showSent=true', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.sent,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            true,
            false,
          );

          expect(result, 'TX > Hello\n');
        });

        test('includes RX marker for received entries when showSent=true', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            true,
            false,
          );

          expect(result, 'RX < Hello\n');
        });

        test('excludes TX/RX markers when showSent=false', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.sent,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Hello\n');
        });
      });

      group('Hex Display Mode', () {
        test('outputs hex format when hexDisplay=true', () {
          final entry = LogEntry(
            Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]), // "Hello"
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            true,
            false,
            false,
            false,
          );

          expect(result, '48 65 6C 6C 6F \n');
        });

        test('hex output includes TX marker when showSent=true', () {
          final entry = LogEntry(
            Uint8List.fromList([0x48, 0x65]),
            LogEntryType.sent,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            true,
            false,
            true,
            false,
          );

          expect(result, 'TX > 48 65 \n');
        });

        test('hex output includes timestamp when showTimestamp=true', () {
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 123);
          final entry = LogEntry(
            Uint8List.fromList([0x48, 0x65]),
            LogEntryType.received,
            timestamp,
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            true,
            true,
            false,
            false,
          );

          expect(result.contains('14:30:45.123'), true);
          expect(result.contains('48 65'), true);
        });

        test('hex output adds soft line breaks every 32 bytes', () {
          // Create 64 bytes of data
          final data = Uint8List(64);
          for (int i = 0; i < 64; i++) {
            data[i] = 0x41; // 'A'
          }
          final entry = LogEntry(data, LogEntryType.received, DateTime.now());

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            true,
            false,
            false,
            false,
          );

          final lines = result.split('\n');
          expect(lines.length, greaterThan(1)); // Has line breaks
        });
      });

      group('Truncation', () {
        test('adds truncation indicator when text exceeds max length', () {
          // Create text longer than maxDisplayLength (5000)
          final longText = 'A' * 5001;
          final entry = LogEntry(
            Uint8List.fromList(longText.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result.contains('... [TRUNCATED]'), true);
        });

        test('does not add truncation indicator when text is under limit', () {
          final entry = LogEntry(
            Uint8List.fromList('Short text'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result.contains('... [TRUNCATED]'), false);
        });

        test('does not truncate in hex mode', () {
          // Create large data
          final data = Uint8List(10000);
          for (int i = 0; i < data.length; i++) {
            data[i] = 0x41;
          }
          final entry = LogEntry(data, LogEntryType.received, DateTime.now());

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            true,
            false,
            false,
            false,
          );

          // Hex mode should not have truncation indicator
          expect(result.contains('... [TRUNCATED]'), false);
        });
      });

      group('Newline Handling', () {
        test('handles single line entry', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Hello\n');
        });

        test('handles multi-line entry', () {
          final entry = LogEntry(
            Uint8List.fromList('Line1\nLine2\nLine3'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Line1\nLine2\nLine3\n');
        });

        test('handles trailing newline', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello\n'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Hello\n\n');
        });

        test('handles consecutive newlines', () {
          final entry = LogEntry(
            Uint8List.fromList('Line1\n\nLine2'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Line1\n\nLine2\n');
        });

        test('timestamp and markers only appear on first line', () {
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 123);
          final entry = LogEntry(
            Uint8List.fromList('Line1\nLine2'.codeUnits),
            LogEntryType.sent,
            timestamp,
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            true,
            true,
            false,
          );

          final lines = result.split('\n');
          // First line has timestamp and TX
          expect(lines[0].contains('14:30:45.123'), true);
          expect(lines[0].contains('TX >'), true);
          // Second line should not have timestamp
          expect(lines[1].contains('14:30:45'), false);
          expect(lines[1].contains('TX >'), false);
        });
      });

      group('WYSIWYG Integration', () {
        test('full WYSIWYG with all options enabled', () {
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 0);
          final entry = LogEntry(
            Uint8List.fromList('Hello World'.codeUnits),
            LogEntryType.sent,
            timestamp,
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            true,
            true,
            false,
          );

          expect(result, '14:30:45.000 TX > Hello World\n');
        });

        test('full WYSIWYG with all options disabled', () {
          final entry = LogEntry(
            Uint8List.fromList('Hello World'.codeUnits),
            LogEntryType.received,
            DateTime.now(),
          );

          final result = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            false,
            false,
            false,
          );

          expect(result, 'Hello World\n');
        });

        test('multiple entries are output in order', () {
          final now = DateTime.now();
          final entries = [
            LogEntry(Uint8List.fromList('First'.codeUnits), LogEntryType.received, now.add(Duration(milliseconds: 1))),
            LogEntry(Uint8List.fromList('Second'.codeUnits), LogEntryType.sent, now.add(Duration(milliseconds: 2))),
            LogEntry(Uint8List.fromList('Third'.codeUnits), LogEntryType.received, now.add(Duration(milliseconds: 3))),
          ];

          final result = LogExportService.generateWysiwygContentForTest(
            entries,
            false,
            false,
            true,
            false,
          );

          expect(result, 'RX < First\nTX > Second\nRX < Third\n');
        });

        test('WYSIWYG matches UI display format', () {
          // This test verifies that export format matches what getSpans renders
          final timestamp = DateTime(2026, 3, 13, 14, 30, 45, 0);
          final entry = LogEntry(
            Uint8List.fromList('Test'.codeUnits),
            LogEntryType.received,
            timestamp,
          );

          // Export format
          final exportResult = LogExportService.generateWysiwygContentForTest(
            [entry],
            false,
            true,
            true,
            false,
          );

          // Should match UI format: timestamp + RX marker + data
          expect(exportResult, '14:30:45.000 RX < Test\n');
        });
      });
    });
  });
}
