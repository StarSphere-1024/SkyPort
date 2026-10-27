import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/log_model.dart';

void main() {
  testWidgets('search highlighting preserves normal newline layout and bytes', (
    tester,
  ) async {
    for (final text in [
      'ansi\r\n',
      'ansi\n',
      'ansi\n\n',
      'ansi\n\nnext',
      'ansi\nnext',
      '😀 ansi\r\n',
    ]) {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final entry = LogEntry(bytes, LogEntryType.sent, DateTime(2026));
      const style = TextStyle(fontSize: 18, height: 1.3);
      final normal = entry.getSpans(
        hexDisplay: false,
        showTimestamp: false,
        showSent: true,
        enableAnsi: false,
        baseStyle: style,
        timestampStyle: style,
        primaryColor: Colors.blue,
        onSurfaceColor: Colors.black,
      );
      final start = text.indexOf('ansi');
      final highlighted = entry.getSearchSpans(
        text: text,
        ranges: [(start: start, end: start + 4)],
        focus: (start: start, end: start + 4),
        showTimestamp: false,
        showSent: true,
        baseStyle: style,
        timestampStyle: style,
        primaryColor: Colors.blue,
        onSurfaceColor: Colors.black,
        matchColor: Colors.yellow,
        selectedColor: Colors.orange,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text.rich(
                  TextSpan(style: style, children: normal),
                  key: const ValueKey('normal'),
                ),
                Text.rich(
                  TextSpan(style: style, children: highlighted),
                  key: const ValueKey('highlighted'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('highlighted'))).height,
        tester.getSize(find.byKey(const ValueKey('normal'))).height,
        reason:
            'Highlight must not introduce a blank line for ${jsonEncode(text)}',
      );
      expect(bytes, utf8.encode(text));
    }
  });
}
