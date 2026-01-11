import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/serial_port_service.dart';
import '../../models/app_error.dart';
import '../../models/connection_status.dart';
import '../../models/ui_settings.dart';
import '../common_providers.dart';
import 'data_log_provider.dart';
import 'error_provider.dart';
import 'serial_config_provider.dart';
import 'ui_settings_provider.dart';

class SerialConnectionNotifier extends Notifier<SerialConnection> {
  StreamSubscription<Uint8List>? _dataSubscription;

  @override
  SerialConnection build() {
    ref.onDispose(() {
      disconnect();
    });
    return SerialConnection();
  }

  /// Establish the serial connection. Formerly `open()`.
  Future<void> connect() async {
    if (state.status != ConnectionStatus.disconnected) {
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
      _dataSubscription = session.stream.listen((data) {
        // Forward received data into the debounced log provider
        ref.read(dataLogProvider.notifier).addReceived(data);
        state = state.copyWith(
          rxBytes: state.rxBytes + data.length,
          lastRxBytes: data.length,
        );
      }, onError: (error) {
        disconnect();
        ref
            .read(errorProvider.notifier)
            .setError(AppErrorType.portDisconnected, error.toString());
      });
      state = state.copyWith(
        status: ConnectionStatus.connected,
        session: session,
      );
    } on SerialPortOpenTimeoutException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.portOpenTimeout, e.message);
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } on SerialPortOpenException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.portOpenFailed, e.message);
      state = state.copyWith(status: ConnectionStatus.disconnected);
    } catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.unknown, e.toString());
      state = state.copyWith(status: ConnectionStatus.disconnected);
    }
  }

  /// Tear down the serial connection. Formerly `close()`.
  Future<void> disconnect() async {
    if (state.status != ConnectionStatus.connected) {
      return;
    }

    ref.read(errorProvider.notifier).clear();
    state = state.copyWith(status: ConnectionStatus.disconnecting);

    final session = state.session;
    final subscriptionToCancel = _dataSubscription;
    _dataSubscription = null;

    try {
      await subscriptionToCancel?.cancel();
      await Future.delayed(const Duration(milliseconds: 200));
      await ref.read(serialPortServiceProvider).close(session);
    } catch (e) {
      if (kDebugMode) {
        print("Error during serial port cleanup: $e");
      }
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.cleanupError, e.toString());
    } finally {
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        session: null,
      );
    }
  }

  // Backward compatibility wrappers (can be removed later)
  @Deprecated('Use connect() instead')
  Future<void> open() => connect();
  @Deprecated('Use disconnect() instead')
  Future<void> close() => disconnect();

  Future<void> send(String data) async {
    if (state.session == null || state.status != ConnectionStatus.connected) {
      return;
    }
    ref.read(errorProvider.notifier).clear();

    final useHex = ref.read(uiSettingsProvider).hexSend;
    final uiSettings = ref.read(uiSettingsProvider);
    Uint8List bytesToSend;

    try {
      if (useHex) {
        bytesToSend = _hexToBytes(data);
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
      final bytesWritten = ref
          .read(serialPortServiceProvider)
          .write(state.session!, bytesToSend, timeoutMs: 100);
      if (bytesWritten > 0) {
        ref
            .read(dataLogProvider.notifier)
            .addSent(bytesToSend.sublist(0, bytesWritten));
      }
      state = state.copyWith(
        txBytes: state.txBytes + bytesWritten,
      );
    } on SerialPortWriteException catch (e) {
      ref
          .read(errorProvider.notifier)
          .setError(AppErrorType.writeFailed, e.message);
    }
  }

  Uint8List _hexToBytes(String hex) {
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

  void resetStats() {
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
