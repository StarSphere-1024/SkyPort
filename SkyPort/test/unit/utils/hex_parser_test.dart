import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/utils/hex_parser.dart';

void main() {
  group('hexToBytes', () {
    group('Valid hex strings', () {
      test('parses simple hex string without spaces', () {
        final result = hexToBytes('48656C6C6F');
        expect(
          result,
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        );
      });

      test('parses hex string with spaces', () {
        final result = hexToBytes('48 65 6C 6C 6F');
        expect(
          result,
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        );
      });

      test('parses hex string with multiple spaces', () {
        final result = hexToBytes('48  65   6C 6C     6F');
        expect(
          result,
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        );
      });

      test('parses single byte', () {
        final result = hexToBytes('41');
        expect(result, Uint8List.fromList([0x41]));
      });

      test('parses empty string', () {
        final result = hexToBytes('');
        expect(result, Uint8List(0));
      });

      test('parses string with only whitespace', () {
        final result = hexToBytes('   ');
        expect(result, Uint8List(0));
      });

      test('handles uppercase hex digits', () {
        final result = hexToBytes('AA BB CC DD EE FF');
        expect(
          result,
          Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
        );
      });

      test('handles lowercase hex digits', () {
        final result = hexToBytes('aa bb cc dd ee ff');
        expect(
          result,
          Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
        );
      });

      test('handles mixed case hex digits', () {
        final result = hexToBytes('Aa Bb Cc Dd Ee Ff');
        expect(
          result,
          Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
        );
      });
    });

    group('Odd length padding', () {
      test('pads single digit with leading zero', () {
        final result = hexToBytes('4 8 6 5');
        expect(
          result,
          Uint8List.fromList([0x04, 0x08, 0x06, 0x05]),
        );
      });

      test('pads odd-length hex pairs', () {
        final result = hexToBytes('486 56C6C6F');
        // '486' -> '0486' -> [0x04, 0x86]
        // '56C6C6F' (7 chars) -> '056C6C6F' -> [0x05, 0x6C, 0x6C, 0x6F]
        expect(
          result,
          Uint8List.fromList([0x04, 0x86, 0x05, 0x6C, 0x6C, 0x6F]),
        );
      });

      test('handles odd length in spaced input', () {
        final result = hexToBytes('4 65 6C 6C 6F');
        expect(
          result,
          Uint8List.fromList([0x04, 0x65, 0x6C, 0x6C, 0x6F]),
        );
      });
    });

    group('Invalid hex strings', () {
      test('throws FormatException for invalid hex characters', () {
        expect(
          () => hexToBytes('GH'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException with descriptive message', () {
        expect(
          () => hexToBytes('48 65 ZZ 6F'),
          throwsA(
            predicate<FormatException>((e) =>
                e.message.contains('Invalid hex value found: "ZZ"')),
          ),
        );
      });

      test('throws for special characters', () {
        expect(
          () => hexToBytes('48!65'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('Edge cases', () {
      test('handles all zeros', () {
        final result = hexToBytes('00 00 00');
        expect(result, Uint8List.fromList([0x00, 0x00, 0x00]));
      });

      test('handles all FFs', () {
        final result = hexToBytes('FF FF FF');
        expect(result, Uint8List.fromList([0xFF, 0xFF, 0xFF]));
      });

      test('handles leading/trailing whitespace', () {
        final result = hexToBytes('  48 65 6C  ');
        expect(
          result,
          Uint8List.fromList([0x48, 0x65, 0x6C]),
        );
      });

      test('handles consecutive hex pairs without spaces', () {
        final result = hexToBytes('000102030405');
        expect(
          result,
          Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]),
        );
      });

      test('handles single digit values in sequence', () {
        final result = hexToBytes('0 1 2 3 4 5 6 7 8 9 A B C D E F');
        expect(
          result,
          Uint8List.fromList([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
          ]),
        );
      });

      test('handles tabs and newlines as whitespace', () {
        final result = hexToBytes('48\t65\n6C\r\n6C\n6F');
        expect(
          result,
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        );
      });

      test('preserves byte order', () {
        final result = hexToBytes('01 02 03 04');
        expect(
          result,
          Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
        );
      });

      test('handles very long hex string', () {
        final longHex = List.generate(256, (i) => i.toRadixString(16).padLeft(2, '0')).join(' ');
        final result = hexToBytes(longHex);
        expect(result.length, 256);
        expect(result[0], 0x00);
        expect(result[255], 0xFF);
      });
    });
  });
}
