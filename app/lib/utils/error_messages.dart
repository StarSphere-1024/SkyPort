import 'dart:io';

import 'package:flutter/services.dart';

import '../host_core.dart';
import '../l10n/app_localizations.dart';
import '../providers/ui_controller.dart';
import '../src/rust/api.dart' as rust;

String localizedError(AppLocalizations l10n, Object error) => switch (error) {
  rust.CoreError() => _coreError(l10n, error),
  CoreHostException(:final error) => _coreError(l10n, error),
  CoreCommandException(:final error) => _coreError(l10n, error),
  HostStartupException(:final failure) => switch (failure) {
    HostFailure.bridgeInitialization => l10n.errorBridgeInitialization,
    HostFailure.preferenceMigration => l10n.errorPreferenceMigration,
    HostFailure.preferencesUnavailable => l10n.errorPreferencesUnavailable,
  },
  FileSystemException() => l10n.errorFileAccess,
  MissingPluginException() => l10n.errorPluginUnavailable,
  PlatformException() => l10n.errorPlatform,
  UnsupportedError() => l10n.errorPlatformUnsupported,
  _ => l10n.errorUnexpected,
};

String _coreError(AppLocalizations l10n, rust.CoreError error) {
  final reason = switch (error.code) {
    rust.ErrorCode.invalidHexCharacter => l10n.invalidHexChars,
    rust.ErrorCode.incompleteHexByte => l10n.hexEvenLength,
    rust.ErrorCode.portNameRequired => l10n.errorPortNameRequired,
    rust.ErrorCode.portNameTooLong => l10n.errorPortNameTooLong,
    rust.ErrorCode.portNameInvalid => l10n.errorPortNameInvalid,
    rust.ErrorCode.baudRateInvalid => l10n.errorBaudRateInvalid,
    rust.ErrorCode.dataBitsInvalid => l10n.errorDataBitsInvalid,
    rust.ErrorCode.stopBitsInvalid => l10n.errorStopBitsInvalid,
    rust.ErrorCode.legacyConfigInvalid => l10n.errorLegacyConfigInvalid,
    rust.ErrorCode.configVersionUnsupported =>
      l10n.errorConfigVersionUnsupported,
    rust.ErrorCode.newlineInvalid => l10n.errorNewlineInvalid,
    rust.ErrorCode.autoSendIntervalInvalid => l10n.errorAutoSendIntervalInvalid,
    rust.ErrorCode.logCapacityInvalid => l10n.errorLogCapacityInvalid,
    rust.ErrorCode.historyTooLong => l10n.errorHistoryTooLong,
    rust.ErrorCode.historyEntryEmpty => l10n.errorHistoryEntryEmpty,
    rust.ErrorCode.historyTooLarge => l10n.errorHistoryTooLarge,
    rust.ErrorCode.configTooLarge => l10n.errorConfigTooLarge,
    rust.ErrorCode.configInvalid => l10n.errorConfigInvalid,
    rust.ErrorCode.configIo => l10n.errorConfigIo,
    rust.ErrorCode.sendTooLarge => l10n.errorSendTooLarge,
    rust.ErrorCode.sendInputTooLarge => l10n.errorSendInputTooLarge,
    rust.ErrorCode.autoSendTooLarge => l10n.errorAutoSendTooLarge,
    rust.ErrorCode.sendEmpty => l10n.errorSendEmpty,
    rust.ErrorCode.noLogsToExport => l10n.errorNoLogsToExport,
    rust.ErrorCode.exportFailed => l10n.errorExportLog,
    rust.ErrorCode.queueCapacityInvalid => l10n.errorQueueCapacityInvalid,
    null => switch (error.kind) {
      rust.ErrorKind.invalidArgument => l10n.errorInvalidArgument,
      rust.ErrorKind.portNotFound => l10n.errorPortNotFound,
      rust.ErrorKind.openFailed => l10n.errorOpenFailed,
      rust.ErrorKind.permissionDenied => l10n.errorPermissionDenied,
      rust.ErrorKind.unsupportedConfiguration =>
        l10n.errorUnsupportedConfiguration,
      rust.ErrorKind.readFailed => l10n.errorReadFailed,
      rust.ErrorKind.disconnected => l10n.errorDisconnected,
      rust.ErrorKind.writeFailed => l10n.errorWriteFailed,
      rust.ErrorKind.timeout => l10n.errorTimeout,
      rust.ErrorKind.closed => l10n.errorClosed,
      rust.ErrorKind.queueOverflow => l10n.errorQueueOverflow,
      rust.ErrorKind.taskFailed => l10n.errorTaskFailed,
      rust.ErrorKind.internal => l10n.errorInternal,
    },
  };
  return error.kind == rust.ErrorKind.writeFailed || error.bytesWritten > 0
      ? l10n.writeFailure(error.bytesWritten, reason)
      : reason;
}

String errorDiagnostics(Object error) => switch (error) {
  CoreHostException(:final error) ||
  CoreCommandException(:final error) => errorDiagnostics(error),
  rust.CoreError() =>
    '${error.kind.name}${error.code == null ? '' : ' / ${error.code!.name}'}: '
        '${error.message} (bytes written: ${error.bytesWritten})',
  _ => '$error',
};
