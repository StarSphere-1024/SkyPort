import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_error.dart';

class ErrorNotifier extends Notifier<AppError?> {
  Timer? _clearTimer;

  @override
  AppError? build() {
    ref.onDispose(() {
      _clearTimer?.cancel();
    });
    return null;
  }

  void setError(AppErrorType type, [String? message]) {
    state = AppError(type, message);
    // Cancel any existing timer
    _clearTimer?.cancel();
    // Auto-clear error after 5 seconds
    _clearTimer = Timer(const Duration(seconds: 5), () {
      if (state?.type == type) {
        state = null;
      }
    });
  }

  void clear() {
    _clearTimer?.cancel();
    state = null;
  }
}

final errorProvider =
    NotifierProvider.autoDispose<ErrorNotifier, AppError?>(ErrorNotifier.new);
