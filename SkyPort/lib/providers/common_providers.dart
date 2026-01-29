import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

// Custom Exception for when no serial ports are available
class NoPortsAvailableException implements Exception {
  final String message;
  NoPortsAvailableException([this.message = 'No ports available.']);

  @override
  String toString() {
    return 'NoPortsAvailableException: $message';
  }
}
