// ignore_for_file: avoid_print

import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ANSI Parser', () {
    test('parses basic ANSI escape sequence for red text', () {
      final text = 'Prefix\x1b[31mHello\x1b[0m World';
      print('Original text: $text');
      final parser = Parser(text);
      print('Pieces count: ${parser.pieces.length}');

      expect(parser.pieces.any((piece) => piece.entity is EscapeCode), true);

      for (final piece in parser.pieces) {
        final substring = text.substring(piece.start, piece.end);
        final isEscape = piece.entity is EscapeCode;
        print(
          'Substring: "$substring", isEscape: $isEscape, State: ${piece.state}',
        );
      }
    });

    test('parses green text ANSI sequence', () {
      final text = '\x1b[32mSuccess\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('parses yellow text ANSI sequence', () {
      final text = '\x1b[33mWarning\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('parses blue text ANSI sequence', () {
      final text = '\x1b[34mInfo\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('parses bold text ANSI sequence', () {
      final text = '\x1b[1mBold Text\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('parses combined bold and color ANSI sequence', () {
      final text = '\x1b[1;31mBold Red\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('handles text without ANSI codes', () {
      final text = 'Plain text without colors';
      final parser = Parser(text);

      // Should have no escape sequences
      final hasEscapes = parser.pieces.any(
        (piece) => piece.entity is EscapeCode,
      );

      expect(hasEscapes, false);
    });

    test('handles empty string', () {
      final text = '';
      final parser = Parser(text);

      expect(parser.pieces.isEmpty, true);
    });

    test('parses multiple ANSI codes in one string', () {
      final text =
          '\x1b[31mRed\x1b[0m \x1b[32mGreen\x1b[0m \x1b[34mBlue\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.length, greaterThan(2));
    });

    test('handles ANSI reset sequence', () {
      final text = '\x1b[0mReset\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });

    test('parses cyan text ANSI sequence', () {
      final text = '\x1b[36mCyan\x1b[0m';
      final parser = Parser(text);

      expect(parser.pieces.isNotEmpty, true);
    });
  });
}
