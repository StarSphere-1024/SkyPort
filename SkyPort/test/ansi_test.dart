import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:test/test.dart';

void main() {
  test('ansi parser test', () {
    final text = 'Prefix\x1b[31mHello\x1b[0m World';
    print('Original text: $text');
    final parser = AnsiParser(text);
    print('Matches count: ${parser.matches.length}');
    for (final match in parser.matches) {
      final substring = text.substring(match.start, match.end);
      final isEscape = substring.startsWith('\x1b');
      print(
          'Substring: "$substring", isEscape: $isEscape, State: ${match.state}');
    }
  });
}
