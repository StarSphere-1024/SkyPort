/// Defines different types of potential errors in the serial workflow
enum AppErrorType {
  none,
  configNotSet,
  portOpenTimeout,
  portOpenFailed,
  portDisconnected,
  writeFailed,
  invalidHexFormat,
  cleanupError,
  unknown;
}

/// A structured error state
class AppError {
  final AppErrorType type;
  final String? rawMessage;

  const AppError(this.type, [this.rawMessage]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppError &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          rawMessage == other.rawMessage;

  @override
  int get hashCode => type.hashCode ^ rawMessage.hashCode;
}
