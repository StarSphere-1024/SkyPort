import 'dart:typed_data';

/// Parses a hex string into a Uint8List of bytes.
///
/// The hex string can contain spaces between bytes. If a hex pair has an odd
/// length, it will be padded with a leading zero.
///
/// Example:
/// ```dart
/// hexToBytes('48 65 6C 6C 6F') // [0x48, 0x65, 0x6C, 0x6C, 0x6F] - "Hello"
/// hexToBytes('48656C6C6F')      // [0x48, 0x65, 0x6C, 0x6C, 0x6F] - "Hello"
/// hexToBytes('4 8 6 5')         // [0x04, 0x08, 0x06, 0x05] - odd padding
/// ```
///
/// Throws [FormatException] if an invalid hex value is encountered.
Uint8List hexToBytes(String hex) {
  final bytes = <int>[];
  // Efficiently split by whitespace and filter out empty strings.
  final parts = hex.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);

  for (var part in parts) {
    // Pad the part if it has an odd length.
    if (part.length % 2 != 0) {
      part = '0$part';
    }

    for (int i = 0; i < part.length; i += 2) {
      final hexPair = part.substring(i, i + 2);
      try {
        bytes.add(int.parse(hexPair, radix: 16));
      } on FormatException {
        // Rethrow with a more informative message.
        throw FormatException('Invalid hex value found: "$hexPair"');
      }
    }
  }
  return Uint8List.fromList(bytes);
}
