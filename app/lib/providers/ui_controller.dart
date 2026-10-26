import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/src/rust/api.dart' as rust;

import '../models/ui_state.dart';
import '../models/log_model.dart';

class CoreBootstrap {
  final rust.CoreHandle handle;
  final rust.AppSnapshot snapshot;
  final rust.SubscriptionHandle subscription;
  const CoreBootstrap(this.handle, this.snapshot, this.subscription);
}

final coreBootstrapProvider = Provider<CoreBootstrap>(
  (ref) => throw StateError(
    'CoreBootstrap was not installed by the application host',
  ),
);
final uiControllerProvider = NotifierProvider<UiController, UiState>(
  UiController.new,
);

final autoSendDraftProvider = NotifierProvider<AutoSendDraftController, String>(
  AutoSendDraftController.new,
);

class AutoSendDraftController extends Notifier<String> {
  @override
  String build() => ref.read(uiControllerProvider).autoSendInput;

  void setDraft(String value) => state = value;

  String forMode(bool hex) {
    if (hex == ref.read(uiControllerProvider).hexSend) return state;
    if (hex) {
      return utf8
          .encode(state)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    }
    final digits = state.replaceAll(RegExp(r'[ \t\n\r\f]+'), '');
    if (digits.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(digits)) {
      return state;
    }
    final bytes = <int>[
      for (var index = 0; index < digits.length; index += 2)
        int.parse(digits.substring(index, index + 2), radix: 16),
    ];
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return state; // Unrepresentable UTF-8 remains visible; never insert replacement bytes.
    }
  }
}

class UiController extends Notifier<UiState> {
  late rust.CoreHandle _handle;
  late rust.SubscriptionHandle _subscription;
  final Map<int, Completer<rust.CoreError?>> _pending = {};
  final Map<int, rust.CoreError?> _terminal = {};
  bool _disposed = false;
  int _subscriptionGeneration = 0;
  int _expiredThrough = 0;
  rust.CoreError? _streamFailure;

  @override
  UiState build() {
    final bootstrap = ref.read(coreBootstrapProvider);
    _handle = bootstrap.handle;
    _subscription = bootstrap.subscription;
    ref.onDispose(() {
      _disposed = true;
      _failPending(
        const rust.CoreError(
          kind: rust.ErrorKind.closed,
          message: 'UI subscription was disposed.',
          bytesWritten: 0,
        ),
      );
      unawaited(rust.cancelSubscription(subscription: _subscription));
    });
    unawaited(_consume());
    return UiState.fromSnapshot(bootstrap.snapshot);
  }

  void _failPending(rust.CoreError error) {
    _subscriptionGeneration++;
    _streamFailure = error;
    for (final request in _pending.values) {
      request.complete(error);
    }
    _pending.clear();
    _terminal.clear();
  }

  void _recordTerminal(rust.Event event) {
    final id = event.requestId;
    if (id == null || id == 0) return;
    final error = switch (event.kind) {
      rust.EventType.commandFailed || rust.EventType.writeFailed => event.error,
      _ => null,
    };
    final pending = _pending.remove(id);
    if (pending != null) {
      pending.complete(error);
      return;
    }
    // Outcomes can arrive before the FFI acceptance reply; retain a bounded window.
    if (_terminal.length == 128) {
      final expired = _terminal.keys.first;
      _terminal.remove(expired);
      if (expired > _expiredThrough) _expiredThrough = expired;
    }
    _terminal[id] = error;
  }

  Future<void> _consume() async {
    try {
      consume:
      while (!_disposed) {
        final reply = await rust.nextEvents(subscription: _subscription);
        if (_disposed) return;
        if (reply.error != null) {
          final error = reply.error!;
          if (error.kind == rust.ErrorKind.queueOverflow) {
            _failPending(error);
            state = state.withBridgeError(error).withDataGap(true);
            if (!await _resubscribe()) return;
            continue;
          }
          _failPending(error);
          if (error.kind != rust.ErrorKind.closed) {
            state = state.withBridgeError(error).withDataGap(true);
          }
          return;
        }
        var sequence = state.sequence;
        for (final event in reply.events) {
          if (event.sequence <= sequence) continue;
          if (event.kind == rust.EventType.queueOverflow ||
              event.sequence != sequence + 1) {
            final error =
                event.error ??
                const rust.CoreError(
                  kind: rust.ErrorKind.queueOverflow,
                  message:
                      'Event sequence gap; resubscribing to current state.',
                  bytesWritten: 0,
                );
            _failPending(error);
            state = state.withBridgeError(error).withDataGap(true);
            if (!await _resubscribe()) return;
            continue consume;
          }
          switch (event.kind) {
            case rust.EventType.commandCompleted:
            case rust.EventType.commandFailed:
            case rust.EventType.dataSent:
            case rust.EventType.writeFailed:
              _recordTerminal(event);
            default:
              break;
          }
          sequence = event.sequence;
        }
        if (sequence != state.sequence) state = state.withEvents(reply.events);
      }
    } catch (error) {
      if (_disposed) return;
      final fatal = rust.CoreError(
        kind: rust.ErrorKind.internal,
        message: 'Bridge polling failed: $error',
        bytesWritten: 0,
      );
      _failPending(fatal);
      state = state.withBridgeError(fatal).withDataGap(true);
    }
  }

  Future<bool> _resubscribe() async {
    await rust.cancelSubscription(subscription: _subscription);
    if (_disposed) return false;
    final reply = await rust.subscribe(handle: _handle);
    if (reply.error != null) {
      _failPending(reply.error!);
      state = state.withBridgeError(reply.error!);
      return false;
    }
    _subscription = reply.subscription!;
    _streamFailure = null;
    LogEntry.clearSpanCache();
    state = UiState.fromSnapshot(reply.snapshot!, dataGap: true);
    return true;
  }

  Future<void> _setConfig({
    String? portName,
    int? baudRate,
    int? dataBits,
    UiParity? parity,
    int? stopBits,
    UiFlowControl? flowControl,
  }) async {
    await _dispatch(
      rust.updateConfig(
        handle: _handle,
        patch: rust.ConfigPatch(
          portName: portName,
          baudRate: baudRate,
          dataBits: dataBits,
          parity: switch (parity) {
            UiParity.none => rust.Parity.none,
            UiParity.odd => rust.Parity.odd,
            UiParity.even => rust.Parity.even,
            null => null,
          },
          stopBits: stopBits,
          flowControl: switch (flowControl) {
            UiFlowControl.none => rust.FlowControl.none,
            UiFlowControl.hardware => rust.FlowControl.hardware,
            UiFlowControl.software => rust.FlowControl.software,
            null => null,
          },
        ),
      ),
    );
  }

  void setPort(String value) => _setConfig(portName: value);
  void setBaudRate(int value) => _setConfig(baudRate: value);
  void setDataBits(int value) => _setConfig(dataBits: value);
  void setParity(UiParity value) => _setConfig(parity: value);
  void setStopBits(int value) => _setConfig(stopBits: value);
  void setAutoReconnect(bool value) =>
      _dispatch(rust.setAutoReconnect(handle: _handle, enabled: value));
  void setFlowControl(UiFlowControl value) => _setConfig(flowControl: value);

  Future<void> connect() async {
    await _dispatch(rust.connect(handle: _handle));
  }

  Future<void> disconnect() async {
    await _dispatch(rust.disconnect(handle: _handle));
  }

  Future<void> listPorts() async {
    await _dispatch(rust.listPorts(handle: _handle));
  }

  Future<void> clearLog() async {
    final error = await _dispatch(rust.clearLog(handle: _handle));
    if (error == null && !_disposed) {
      state = state.withDataGap(false);
    }
  }

  Future<void> send(String value) async {
    await _dispatch(rust.sendInput(handle: _handle, input: value));
  }

  static rust.Newline _coreNewline(UiNewline value) => switch (value) {
    UiNewline.none => rust.Newline.none,
    UiNewline.lf => rust.Newline.lf,
    UiNewline.cr => rust.Newline.cr,
    UiNewline.crlf => rust.Newline.crLf,
  };

  Future<void> setSendSettings({
    bool? hex,
    UiNewline? newline,
    bool? appendNewline,
    bool? enabled,
    int? intervalMs,
    String? input,
  }) async {
    await _dispatch(
      rust.updateConfig(
        handle: _handle,
        patch: rust.ConfigPatch(
          hexSend: hex,
          newline: newline == null ? null : _coreNewline(newline),
          appendNewline: appendNewline,
          autoSendEnabled: enabled,
          autoSendIntervalMs: intervalMs,
          autoSendInput: input,
        ),
      ),
    );
  }

  Future<void> setAutoSendInput(String input) async {
    await _dispatch(
      rust.updateConfig(
        handle: _handle,
        patch: rust.ConfigPatch(autoSendInput: input),
      ),
    );
  }

  Future<void> setLogCapacity(int megabytes) async {
    await _dispatch(
      rust.updateConfig(
        handle: _handle,
        patch: rust.ConfigPatch(logCapacityBytes: megabytes * 1024 * 1024),
      ),
    );
  }

  Future<void> exportLog(String path, rust.ExportOptions options) async {
    final error = await _dispatch(
      rust.exportLog(handle: _handle, path: path, options: options),
    );
    if (error != null) throw CoreCommandException(error);
  }

  Future<rust.CoreError?> _dispatch(
    Future<rust.DispatchReply> operation,
  ) async {
    final generation = _subscriptionGeneration;
    try {
      return await _capture(await operation, generation);
    } catch (error) {
      final fatal = rust.CoreError(
        kind: rust.ErrorKind.internal,
        message: 'Bridge command failed: $error',
        bytesWritten: 0,
      );
      if (!_disposed) state = state.withBridgeError(fatal);
      return fatal;
    }
  }

  Future<rust.CoreError?> _capture(
    rust.DispatchReply reply,
    int generation,
  ) async {
    if (reply.error != null) {
      if (!_disposed) state = state.withBridgeError(reply.error!);
      return reply.error;
    }
    final id = reply.requestId!;
    if (_terminal.containsKey(id)) return _terminal.remove(id);
    if (_disposed ||
        generation != _subscriptionGeneration ||
        _streamFailure != null) {
      return _streamFailure ??
          const rust.CoreError(
            kind: rust.ErrorKind.queueOverflow,
            message: 'Command completion was interrupted by resubscription.',
            bytesWritten: 0,
          );
    }
    if (id <= _expiredThrough) {
      return const rust.CoreError(
        kind: rust.ErrorKind.queueOverflow,
        message: 'Command outcome is outside the retained completion window.',
        bytesWritten: 0,
      );
    }
    final completer = Completer<rust.CoreError?>();
    _pending[id] = completer;
    // Terminal events already project their one-shot notices in _consume.
    return completer.future;
  }
}

class CoreCommandException implements Exception {
  const CoreCommandException(this.error);
  final rust.CoreError error;

  @override
  String toString() => '${error.kind.name}: ${error.message}';
}
