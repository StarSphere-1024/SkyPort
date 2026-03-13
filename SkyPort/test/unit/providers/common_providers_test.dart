import 'package:flutter_test/flutter_test.dart';

import 'package:skyport/providers/common_providers.dart';

void main() {
  group('NoPortsAvailableException', () {
    test('creates exception with default message', () {
      // Act
      final exception = NoPortsAvailableException();

      // Assert
      expect(exception.toString(), 'NoPortsAvailableException: No ports available.');
    });

    test('creates exception with custom message', () {
      // Arrange
      const customMessage = 'Custom error message';

      // Act
      final exception = NoPortsAvailableException(customMessage);

      // Assert
      expect(exception.toString(), 'NoPortsAvailableException: $customMessage');
    });
  });
}
