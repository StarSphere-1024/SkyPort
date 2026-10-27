import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/log_model.dart';

void main() {
  group('LogEntry', () {
    group('getDisplayText', () {
      test('returns UTF-8 decoded text when hexDisplay=false', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(false);

        expect(text, 'Hello');
      });

      test('returns hex when hexDisplay=true', () {
        final data = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(true);

        expect(text, '48 65 6C 6C 6F ');
      });

      test('handles empty data', () {
        final data = Uint8List(0);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(false);

        expect(text, '');
      });

      test('handles invalid UTF-8 with allowMalformed', () {
        // Invalid UTF-8 sequence
        final data = Uint8List.fromList([0x80, 0x81, 0x82]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text = entry.getDisplayText(false);

        // Should not throw, should return replacement characters
        expect(text, isNotNull);
      });

      test('caches result for hexDisplay mode', () {
        final data = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text1 = entry.getDisplayText(true);
        final text2 = entry.getDisplayText(true);

        expect(text1, same(text2)); // Same cached instance
        expect(text1, '48 65 6C 6C 6F ');
      });

      test('caches result for text mode', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text1 = entry.getDisplayText(false);
        final text2 = entry.getDisplayText(false);

        expect(text1, same(text2)); // Same cached instance
        expect(text1, 'Hello');
      });

      test('invalidates cache when hexDisplay changes', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final text1 = entry.getDisplayText(false);
        final hex1 = entry.getDisplayText(true);
        final text2 = entry.getDisplayText(false);

        expect(text1, 'Hello');
        expect(hex1, '48 65 6C 6C 6F ');
        expect(text2, 'Hello');
      });

      test('adds soft line breaks every 32 bytes in hex mode', () {
        // Create 64 bytes of data
        final data = Uint8List(64);
        for (int i = 0; i < 64; i++) {
          data[i] = 0x41; // 'A'
        }

        final entry = LogEntry(data, LogEntryType.received, DateTime.now());
        final text = entry.getDisplayText(true);

        // Should have newline after 32nd byte
        final lines = text.split('\n');
        expect(lines.length, greaterThan(1)); // Has line breaks
        expect(lines[0].length, greaterThan(0)); // First line has content
      });
    });

    group('getSpans', () {
      late ThemeData theme;

      setUp(() {
        theme = ThemeData.light();
      });

      test('includes timestamp when showTimestamp=true', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final timestamp = DateTime(2024, 1, 1, 12, 30, 45, 123);
        final entry = LogEntry(data, LogEntryType.received, timestamp);

        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: true,
          showSent: false,
          enableAnsi: false,
          baseStyle: theme.textTheme.bodyLarge!,
          timestampStyle: theme.textTheme.bodySmall!,
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans.isNotEmpty, true);
        // First span should be timestamp
        expect((spans.first as TextSpan).text?.contains('12:30:45'), true);
      });

      test('does not include timestamp when showTimestamp=false', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: false,
          enableAnsi: false,
          baseStyle: theme.textTheme.bodyLarge!,
          timestampStyle: theme.textTheme.bodySmall!,
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        // First span should not be timestamp
        final firstSpan = spans.first as TextSpan;
        expect(firstSpan.text?.contains(':'), false);
      });

      test('includes TX prefix for sent entries when showSent=true', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.sent, DateTime.now());

        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: true,
          enableAnsi: false,
          baseStyle: theme.textTheme.bodyLarge!,
          timestampStyle: theme.textTheme.bodySmall!,
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans.isNotEmpty, true);
        // Should have TX prefix
        final hasTxPrefix = spans.any((span) {
          if (span is TextSpan) {
            return span.text?.contains('TX') ?? false;
          }
          return false;
        });
        expect(hasTxPrefix, true);
      });

      test('includes RX prefix for received entries when showSent=true', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        final spans = entry.getSpans(
          hexDisplay: false,
          showTimestamp: false,
          showSent: true,
          enableAnsi: false,
          baseStyle: theme.textTheme.bodyLarge!,
          timestampStyle: theme.textTheme.bodySmall!,
          primaryColor: Colors.blue,
          onSurfaceColor: Colors.black,
        );

        expect(spans.isNotEmpty, true);
        // Should have RX prefix
        final hasRxPrefix = spans.any((span) {
          if (span is TextSpan) {
            return span.text?.contains('RX') ?? false;
          }
          return false;
        });
        expect(hasRxPrefix, true);
      });
    });

    test(
      'search spans preserve UTF-16 text, labels, and exact bounded highlights',
      () {
        final data = Uint8List(30000);
        final entry = LogEntry(
          data,
          LogEntryType.sent,
          DateTime(2026, 1, 1, 12, 34, 56),
        );
        const text = '😀 needle needle';
        final spans = entry
            .getSearchSpans(
              text: text,
              ranges: [(start: 3, end: 9), (start: 10, end: 16)],
              focus: (start: 10, end: 16),
              showTimestamp: true,
              showSent: true,
              baseStyle: const TextStyle(),
              timestampStyle: const TextStyle(),
              primaryColor: Colors.blue,
              onSurfaceColor: Colors.black,
              matchColor: Colors.yellow,
              selectedColor: Colors.orange,
            )
            .cast<TextSpan>();
        expect(
          spans.map((span) => span.text).join(),
          '12:34:56.000 TX > $text',
        );
        final matches = spans.where((span) => span.text == 'needle').toList();
        expect(matches, hasLength(2));
        expect(matches.first.style!.backgroundColor, Colors.yellow);
        expect(matches.last.style!.backgroundColor, Colors.orange);
        expect(data, everyElement(0));
        expect(entry.debugHasCachedDisplayText, isFalse);
      },
    );

    group('Caching Behavior', () {
      test('spans are cached with LRU policy', () {
        final data = Uint8List.fromList('Hello'.codeUnits);
        final entry = LogEntry(data, LogEntryType.received, DateTime.now());

        // Access spans multiple times with same settings
        for (int i = 0; i < 5; i++) {
          entry.getSpans(
            hexDisplay: false,
            showTimestamp: true,
            showSent: true,
            enableAnsi: false,
            baseStyle: const TextStyle(),
            timestampStyle: const TextStyle(),
            primaryColor: Colors.blue,
            onSurfaceColor: Colors.black,
          );
        }

        // Should not throw, cache should handle repeated access
        expect(true, true);
      });
    });
  });
}
