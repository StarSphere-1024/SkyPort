import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
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

  /// Maps an [AppError] to a localized error message using [loc].
  /// Returns an empty string if the error is null or of type [AppErrorType.none].
  String getErrorMessage(AppLocalizations loc) {
    final error = state;
    if (error == null || error.type == AppErrorType.none) return '';

    switch (error.type) {
      case AppErrorType.configNotSet:
        return loc.errConfigNotSet;
      case AppErrorType.portOpenTimeout:
        return loc.errPortOpenTimeout(error.rawMessage ?? '');
      case AppErrorType.portOpenFailed:
        return loc.errPortOpenFailed(error.rawMessage ?? '');
      case AppErrorType.portDisconnected:
        return loc.errPortDisconnected(error.rawMessage ?? '');
      case AppErrorType.writeFailed:
        return loc.errWriteFailed(error.rawMessage ?? '');
      case AppErrorType.invalidHexFormat:
        return loc.errInvalidHexFormat;
      case AppErrorType.cleanupError:
        return loc.errCleanupError(error.rawMessage ?? '');
      case AppErrorType.unknown:
        return loc.errUnknown(error.rawMessage ?? '');
      case AppErrorType.none:
        return '';
    }
  }
}

final errorProvider =
    NotifierProvider.autoDispose<ErrorNotifier, AppError?>(ErrorNotifier.new);
