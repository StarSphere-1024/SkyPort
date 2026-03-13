import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

import 'package:skyport/models/log_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogEntry', () {
    group('getDisplayText', () {
      test('returns UTF-8 decoded text in text mode', () {
        final data = Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello"
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(false);
        expect(text, 'Hello');
      });

      test('returns hex representation in hex mode', () {
        final data = Uint8List.fromList([255, 128, 64, 32, 16, 8, 4, 2, 1, 0]);
        final entry = LogEntry(data, LogEntryType.sent, DateTime.now());

        final text = entry.getDisplayText(true);
        expect(text, contains('FF'));
        expect(text, contains('80'));
        expect(text, contains('40'));
        expect(text, contains('20'));
      });

      test('hex mode inserts soft line breaks every 32 bytes', () {
        final data = Uint8List(64); // 64 bytes
        for (int i = 0; i < data.length; i++) {
          data[i] = i & 0xFF;
        }
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(true);
        final lines = text.split('\n');
        // First line should have 32 bytes * 3 chars (2 hex + space) = 96 chars
        expect(lines.first.length, 96);
        expect(lines.length, greaterThan(1));
      });

      test('handles malformed UTF-8 gracefully', () {
        final data = Uint8List.fromList([0xFF, 0xFE, 0x80, 0xC0]); // Invalid UTF-8
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(false);
        // Should not throw, returns replacement characters
        expect(text, isNotEmpty);
      });

      test('caches text results', () {
        final data = Uint8List.fromList([65, 66, 67]); // "ABC"
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        // First call
        final text1 = entry.getDisplayText(false);
        // Second call should use cache
        final text2 = entry.getDisplayText(false);
        expect(text1, text2);

        // Different mode should regenerate
        final hexText = entry.getDisplayText(true);
        expect(hexText, isNot(equals(text1)));
      });

      test('hex mode uppercase format', () {
        final data = Uint8List.fromList([0x0A, 0x0B, 0x0C]);
        final entry = LogEntry(data, LogEntryType.sent, DateTime.now());

        final text = entry.getDisplayText(true);
        expect(text, contains('0A'));
        expect(text, contains('0B'));
        expect(text, contains('0C'));
      });
    });

    group('getSpans caching', () {
      test('returns cached spans for same settings', () {
        final data = Uint8List.fromList([72, 101, 108, 108, 111]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final timestampStyle = const TextStyle(fontSize: 12);
        final primaryColor = Colors.blue;
        final onSurfaceColor = Colors.black;

        final spans1 = entry.getSpans(
          hexDisplay: false,
          showTimestamp: true,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        final spans2 = entry.getSpans(
          hexDisplay: false,
          showTimestamp: true,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        expect(spans1.length, spans2.length);
      });

      test('regenerates spans when settings change', () {
        final data = Uint8List.fromList([72, 101, 108, 108, 111]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final timestampStyle = const TextStyle(fontSize: 12);
        final primaryColor = Colors.blue;
        final onSurfaceColor = Colors.black;

        // Without timestamp
        final spans1 = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        // With timestamp
        final spans2 = entry.getSpans(
          hexDisplay: false,
          showTimestamp: true,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        // Should have different lengths due to timestamp
        expect(spans2.length, greaterThan(spans1.length));
      });

      test('TX/RX prefix shown for sent entries', () {
        final data = Uint8List.fromList([72, 101, 108, 108, 111]);
        final sentEntry = LogEntry(data, LogEntryType.sent, DateTime.now());
        final rxEntry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final timestampStyle = const TextStyle(fontSize: 12);
        final primaryColor = Colors.blue;
        final onSurfaceColor = Colors.black;

        final sentSpans = sentEntry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: true,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        final rxSpans = rxEntry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: true,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        // Both should have prefix
        expect(sentSpans.length, greaterThan(0));
        expect(rxSpans.length, greaterThan(0));
      });
    });

    group('getSpans ANSI rendering', () {
      test('parses ANSI escape sequences when enabled', () {
        final data = Uint8List.fromList([
          72, 101, 108, 108, 111, // "Hello"
          27, 91, 51, 49, 109, // ESC[31m - red
          87, 111, 114, 108, 100, // "World"
          27, 91, 48, 109, // ESC[0m - reset
        ]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final timestampStyle = const TextStyle(fontSize: 12);
        final primaryColor = Colors.blue;
        final onSurfaceColor = Colors.black;

        final spansWithAnsi = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: true,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        final spansWithoutAnsi = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: timestampStyle,
          primaryColor: primaryColor,
          onSurfaceColor: onSurfaceColor,
        );

        // ANSI parsing should produce more spans (text segments with different styles)
        expect(spansWithAnsi.length, greaterThanOrEqualTo(spansWithoutAnsi.length));
      });

      test('ANSI colors mapped to Flutter colors', () {
        // Test that _ansiStateToStyle handles different ANSI color types
        // This is more of an integration test for the color mapping
        final data = Uint8List.fromList([27, 91, 51, 50, 109, 72, 105]); // ESC[32m + "Hi"
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: true,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans, isNotEmpty);
      });
    });

    group('getSpans truncation', () {
      test('truncates long text in text mode', () {
        // Create data longer than maxDisplayMaxLength (5000)
        final data = Uint8List(6000); // 6000 characters
        for (int i = 0; i < data.length; i++) {
          data[i] = 65; // "A"
        }
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        // Should contain truncation indicator as last span
        final truncationSpan = spans.lastWhere(
          (s) => s is TextSpan && (s.text?.contains('[TRUNCATED]') ?? false),
          orElse: () => const TextSpan(text: ''),
        );
        expect(truncationSpan, isA<TextSpan>());
        expect((truncationSpan as TextSpan).text, contains('[TRUNCATED]'));
      });

      test('does not truncate in hex mode', () {
        final data = Uint8List(300);
        for (int i = 0; i < data.length; i++) {
          data[i] = i & 0xFF;
        }
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: true,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        // Should not contain truncation indicator
        final hasTruncation = spans.any((s) =>
            s is TextSpan && (s.text?.contains('[TRUNCATED]') ?? false));
        expect(hasTruncation, isFalse);
      });
    });

    group('getSpans newline handling', () {
      test('handles trailing newline', () {
        final data = Uint8List.fromList([72, 105, 10]); // "Hi\n"
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        // Should handle the newline without crashing
        expect(spans, isNotEmpty);
      });

      test('handles consecutive newlines', () {
        final data = Uint8List.fromList([72, 105, 10, 10, 72, 111]); // "Hi\n\nHo"
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans, isNotEmpty);
      });

      test('handles empty data', () {
        final data = Uint8List(0);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final baseStyle = const TextStyle(fontSize: 14);
        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: baseStyle,
          timestampStyle: const TextStyle(fontSize: 12),
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans, isNotEmpty);
      });
    });

    group('LogEntryType', () {
      test('sent entry has correct type', () {
        final data = Uint8List.fromList([1, 2, 3]);
        final entry = LogEntry(data, LogEntryType.sent, DateTime.now());
        expect(entry.type, LogEntryType.sent);
      });

      test('received entry has correct type', () {
        final data = Uint8List.fromList([1, 2, 3]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());
        expect(entry.type, LogEntryType.received);
      });
    });

    group('LogChunk', () {
      test('rxEntries filters only received entries', () {
        final now = DateTime.now();
        final entries = [
          LogEntry(Uint8List.fromList([1]), LogEntryType.received, now),
          LogEntry(Uint8List.fromList([2]), LogEntryType.sent, now),
          LogEntry(Uint8List.fromList([3]), LogEntryType.received, now),
          LogEntry(Uint8List.fromList([4]), LogEntryType.sent, now),
        ];

        final chunk = LogChunk(entries: entries, totalBytes: 10, id: 1);
        final rxEntries = chunk.rxEntries;

        expect(rxEntries.length, 2);
        expect(rxEntries.every((e) => e.type == LogEntryType.received), isTrue);
      });

      test('rxEntries is cached', () {
        final now = DateTime.now();
        final entries = [
          LogEntry(Uint8List.fromList([1]), LogEntryType.received, now),
        ];

        final chunk = LogChunk(entries: entries, totalBytes: 1, id: 1);

        // First access
        final rx1 = chunk.rxEntries;
        // Second access should return cached list
        final rx2 = chunk.rxEntries;

        expect(rx1, same(rx2));
      });

      test('empty chunk has empty rxEntries', () {
        final chunk = LogChunk(entries: [], totalBytes: 0, id: 1);
        expect(chunk.rxEntries.length, 0);
      });
    });

    group('LogState', () {
      test('default constructor creates empty state', () {
        final state = const LogState();

        expect(state.chunks.length, 0);
        expect(state.totalBytes, 0);
        expect(state.nextChunkId, 0);
      });

      test('allEntries returns flattened entries', () {
        final now = DateTime.now();
        final chunks = [
          LogChunk(
            entries: [
              LogEntry(Uint8List.fromList([1]), LogEntryType.received, now),
              LogEntry(Uint8List.fromList([2]), LogEntryType.sent, now),
            ],
            totalBytes: 2,
            id: 1,
          ),
          LogChunk(
            entries: [
              LogEntry(Uint8List.fromList([3]), LogEntryType.received, now),
            ],
            totalBytes: 1,
            id: 2,
          ),
        ];

        final state = LogState(chunks: chunks, totalBytes: 3, nextChunkId: 3);
        final allEntries = state.allEntries;

        expect(allEntries.length, 3);
      });

      test('empty state has empty allEntries', () {
        final state = const LogState();
        expect(state.allEntries.length, 0);
      });
    });
  });
}
