import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/serial_port_service.dart';
import '../../models/app_error.dart';
import '../../models/connection_status.dart';
import '../../models/ui_settings.dart';
import '../../utils/hex_parser.dart';
import '../../utils/constants.dart';
import 'data_log_provider.dart';
import 'error_provider.dart';
import 'serial_config_provider.dart';
import 'ui_settings_provider.dart';

class SerialConnectionNotifier extends Notifier<SerialConnection> {
  StreamSubscription<Uint8List>? _dataSubscription;
  Timer? _reconnectTimer;
  bool _mounted = true;

  @override
  SerialConnection build() {
    ref.onDispose(() {
      _mounted = false;
      _cleanup();
    });

    // Listen for port availability to auto-reconnect
    ref.listen(availablePortsProvider, (previous, next) {
      if (!_mounted) return;

      final ports = next.asData?.value ?? [];
      if (state.status == ConnectionStatus.reconnecting) {
        final config = ref.read(serialConfigProvider);
        if (config != null && ports.contains(config.portName)) {
          // Schedule reconnect asynchronously to avoid calling during dispose
          Future.microtask(() {
            if (_mounted) {
              connect();
            }
          });
        }
      }
    });

    return SerialConnection();
  }

  /// Cleanup all resources and cancel pending operations
  void _cleanup() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Cancel data subscription synchronously
    _dataSubscription?.cancel();
    _dataSubscription = null;

    // Note: We don't close the session here to avoid accessing ref during dispose
    // The session will be closed by the service when the container is disposed
  }

  /// Establish the serial connection. Formerly `open()`.
  Future<void> connect() async {
    if (!_mounted) return;

    if (state.status != ConnectionStatus.disconnected &&
        state.status != ConnectionStatus.reconnecting) {
      return;
    }
    ref.read(errorProvider.notifier).clear();
    state = state.copyWith(status: ConnectionStatus.connecting);

    final config = ref.read(serialConfigProvider);
    if (config == null) {
      ref.read(errorProvider.notifier).setError(AppErrorType.configNotSet);
      state = state.copyWith(status: ConnectionStatus.disconnected);
      return;
    }
    final service = ref.read(serialPortServiceProvider);
    try {
      final session = await service.open(config);
      // Check if disposed during async operation
      if (!_mounted) return;

      _dataSubscription = session.stream.listen((data) {
        if (!_mounted) return;

        // Forward received data into the debounced log provider
        ref.read(dataLogProvider.notifier).addReceived(data);
        if (_mounted) {
          state = state.copyWith(
            rxBytes: state.rxBytes + data.length,
            lastRxBytes: data.length,
          );
        }
      }, onError: (error) {
        if (!_mounted) return;

        final config = ref.read(serialConfigProvider);
        if (config?.autoReconnect == true) {
          _internalDisconnect(status: ConnectionStatus.reconnecting);
        } else {
          disconnect();
          ref
              .read(errorProvider.notifier)
              .setError(AppErrorType.portDisconnected, error.toString());
        }
      });
      state = state.copyWith(
        status: ConnectionStatus.connected,
        session: session,
      );
    } on SerialPortOpenTimeoutException catch (e) {
      if (_mounted) {
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.portOpenTimeout, e.message);
        state = state.copyWith(status: ConnectionStatus.disconnected);
      }
    } on SerialPortOpenException catch (e) {
      if (_mounted) {
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.portOpenFailed, e.message);
        state = state.copyWith(status: ConnectionStatus.disconnected);
      }
    } catch (e) {
      if (_mounted) {
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.unknown, e.toString());
        state = state.copyWith(status: ConnectionStatus.disconnected);
      }
    }
  }

  /// Tear down the serial connection. Formerly `close()`.
  Future<void> disconnect() async {
    if (!_mounted) return;
    await _internalDisconnect(status: ConnectionStatus.disconnected);
  }

  Future<void> _internalDisconnect({required ConnectionStatus status}) async {
    if (!_mounted) return;

    if (state.status != ConnectionStatus.connected &&
        state.status != ConnectionStatus.reconnecting) {
      // Allow disconnecting from reconnecting state (e.g. user cancels)
      if (state.status == ConnectionStatus.reconnecting &&
          status == ConnectionStatus.disconnected) {
        if (_mounted) {
          state = state.copyWith(status: ConnectionStatus.disconnected);
        }
        return;
      }
      return;
    }

    ref.read(errorProvider.notifier).clear();
    // Only show disconnecting status if we were connected
    if (state.status == ConnectionStatus.connected && _mounted) {
      state = state.copyWith(status: ConnectionStatus.disconnecting);
    }

    final session = state.session;
    final subscriptionToCancel = _dataSubscription;
    _dataSubscription = null;

    try {
      await subscriptionToCancel?.cancel();
      if (status == ConnectionStatus.disconnected) {
        await Future.delayed(Duration(milliseconds: SkyPortConstants.connectionSettleDelayMs));
      }
      if (session != null) {
        await ref.read(serialPortServiceProvider).close(session);
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error during serial port cleanup: $e");
      }

      // Only report if strictly disconnecting to avoid UI noise during reconnect.
      if (status == ConnectionStatus.disconnected && _mounted) {
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.cleanupError, e.toString());
      }
    } finally {
      if (_mounted) {
        state = state.copyWith(
          status: status,
          session: null,
        );
      }
    }
  }

  // Backward compatibility wrappers (can be removed later)
  @Deprecated('Use connect() instead')
  Future<void> open() => connect();
  @Deprecated('Use disconnect() instead')
  Future<void> close() => disconnect();

  Future<void> send(String data) async {
    if (!_mounted) return;

    if (state.session == null || state.status != ConnectionStatus.connected) {
      return;
    }
    ref.read(errorProvider.notifier).clear();

    final useHex = ref.read(uiSettingsProvider).hexSend;
    final uiSettings = ref.read(uiSettingsProvider);
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = hexToBytes(data);
      } else {
        var textToSend = data;
        if (uiSettings.appendNewline) {
          String newline;
          switch (uiSettings.newlineMode) {
            case NewlineMode.lf:
              newline = '\n';
              break;
            case NewlineMode.cr:
              newline = '\r';
              break;
            case NewlineMode.crlf:
              newline = '\r\n';
              break;
          }
          textToSend = '$textToSend$newline';
        }
        bytesToSend = Uint8List.fromList(utf8.encode(textToSend));
      }
    } catch (e) {
      ref.read(errorProvider.notifier).setError(AppErrorType.invalidHexFormat);
      return;
    }

    try {
      final bytesWritten =
          state.session!.write(bytesToSend, timeoutMs: SkyPortConstants.defaultWriteTimeoutMs);
      if (bytesWritten > 0) {
        ref
            .read(dataLogProvider.notifier)
            .addSent(bytesToSend.sublist(0, bytesWritten));
      }
      if (_mounted) {
        state = state.copyWith(
          txBytes: state.txBytes + bytesWritten,
        );
      }
    } on SerialPortWriteException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.writeFailed, e.message);
    }
  }

  void resetStats() {
    if (!_mounted) return;

    state = state.copyWith(
      rxBytes: 0,
      txBytes: 0,
      lastRxBytes: 0,
    );
  }
}

final serialConnectionProvider =
    NotifierProvider.autoDispose<SerialConnectionNotifier, SerialConnection>(
        SerialConnectionNotifier.new);
