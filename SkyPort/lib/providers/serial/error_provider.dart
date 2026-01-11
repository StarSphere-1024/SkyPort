import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_error.dart';

class ErrorNotifier extends Notifier<AppError?> {
  @override
  AppError? build() => null;

  void setError(AppErrorType type, [String? message]) {
    state = AppError(type, message);
    // Auto-clear error after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (state?.type == type) {
        state = null;
      }
    });
  }

  void clear() {
    state = null;
  }
}

final errorProvider =
    NotifierProvider.autoDispose<ErrorNotifier, AppError?>(ErrorNotifier.new);
