import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/src/rust/frb_generated.dart';
import 'providers/ui_controller.dart';
import 'services/app_logger.dart';

const _hostChannel = MethodChannel('skyport/host');
const _migrationKey = 'skyport_core_config_migrated';

Future<CoreBootstrap> createCoreFromHost(
  SharedPreferences prefs, {
  String? dataDirectory,
}) async {
  await RustLib.init(externalLibrary: ExternalLibrary.open(_bridgePath()));
  final support = dataDirectory == null
      ? await getApplicationSupportDirectory()
      : null;
  final legacy = prefs.getBool(_migrationKey) == true
      ? null
      : _legacyConfig(prefs);
  final created = await rust.createCore(
    dataDirectory: dataDirectory ?? support!.path,
    legacyConfig: legacy,
  );
  if (created.error != null) throw CoreHostException(created.error!);
  final handle = created.handle!;
  rust.SubscribeReply? subscribed;
  try {
    subscribed = await rust.subscribe(handle: handle);
    if (subscribed.error != null) throw CoreHostException(subscribed.error!);
    if (legacy != null && await prefs.setBool(_migrationKey, true) == false) {
      throw StateError('Failed to acknowledge migrated legacy preferences.');
    }
    return CoreBootstrap(
      handle,
      subscribed.snapshot!,
      subscribed.subscription!,
    );
  } catch (_) {
    if (subscribed?.subscription != null) {
      await rust.cancelSubscription(subscription: subscribed!.subscription!);
    }
    await rust.closeCore(handle: handle);
    rethrow;
  }
}

Future<void> installHostCloseHandler(CoreBootstrap? bootstrap) async {
  AppLifecycleListener? listener;
  Future<bool>? closing;
  var closed = false;
  Future<bool> close() async {
    if (closed) return true;
    if (bootstrap == null) {
      closed = true;
      listener?.dispose();
      return true;
    }
    closing ??= () async {
      try {
        final result = await rust.closeCore(handle: bootstrap.handle);
        if (result.error != null) {
          AppLogger.instance.error(
            'Core close failed',
            error: result.error!.message,
          );
          final snapshot = await rust.snapshot(handle: bootstrap.handle);
          if (snapshot.error?.kind != rust.ErrorKind.closed) return false;
        }
        closed = true;
        listener?.dispose();
        return true;
      } catch (error) {
        AppLogger.instance.error('Bridge close failed', error: error);
        return false;
      }
    }();
    final result = await closing!;
    if (!result) closing = null;
    return result;
  }

  listener = AppLifecycleListener(
    onExitRequested: () async =>
        await close() ? AppExitResponse.exit : AppExitResponse.cancel,
  );
  _hostChannel.setMethodCallHandler((call) async {
    if (call.method != 'requestClose') throw MissingPluginException();
    return close();
  });
}

String _bridgePath() {
  if (!Platform.isWindows && !Platform.isLinux) {
    throw UnsupportedError(
      'The Rust bridge is not configured for ${Platform.operatingSystem}.',
    );
  }
  final executable = Platform.resolvedExecutable;
  final separator = Platform.pathSeparator;
  final directory = executable.substring(0, executable.lastIndexOf(separator));
  final filename = Platform.isWindows
      ? 'skyport_flutter_bridge.dll'
      : 'libskyport_flutter_bridge.so';
  final bundled = Platform.isWindows
      ? '$directory$separator$filename'
      : '$directory${separator}lib$separator$filename';
  if (File(bundled).existsSync()) return bundled;
  throw FileSystemException(
    'Bundled Rust bridge library not found: $bundled',
  );
}

rust.LegacyConfig _legacyConfig(SharedPreferences prefs) => rust.LegacyConfig(
  portName: prefs.getString('serial_port_name'),
  baudRate: prefs.getInt('serial_baud_rate'),
  dataBits: prefs.getInt('serial_data_bits'),
  parity: prefs.getInt('serial_parity'),
  stopBits: prefs.getInt('serial_stop_bits'),
  autoReconnect: prefs.getBool('serial_auto_reconnect'),
  hexSend: prefs.getBool('ui_hex_send'),
  appendNewline: prefs.getBool('ui_append_newline'),
  newlineMode: prefs.getInt('ui_newline_mode'),
  autoSendEnabled: prefs.getBool('ui_auto_send_enabled'),
  autoSendIntervalMs: prefs.getInt('ui_auto_send_interval_ms'),
  logBufferMegabytes: prefs.getInt('ui_log_buffer_size'),
  history: prefs.getStringList('send_input_history'),
);

Future<void> runKernelSmoke(List<String> args) async {
  String? resultPath;
  for (final argument in args) {
    if (argument.startsWith('--kernel-smoke-result=')) {
      resultPath = argument.substring('--kernel-smoke-result='.length);
      break;
    }
  }
  if (resultPath != null && !File(resultPath).isAbsolute) {
    throw ArgumentError('--kernel-smoke-result must be an absolute path');
  }
  if (resultPath != null) {
    final resultFile = File(resultPath);
    if (await resultFile.exists()) await resultFile.delete();
  }
  final temp = await Directory.systemTemp.createTemp('skyport-kernel-smoke-');
  rust.CoreHandle? handle;
  rust.SubscriptionHandle? subscription;
  const sentinel = 'SKYPORT_KERNEL_SMOKE_OK';
  try {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_bridgePath()));
    final create = await rust.createCore(
      dataDirectory: temp.path,
      legacyConfig: null,
    );
    if (create.error != null || create.handle == null) {
      throw StateError('core create failed: ${create.error?.message}');
    }
    final core = create.handle!;
    handle = core;
    final initial = await rust.subscribe(handle: core);
    if (initial.error != null ||
        initial.snapshot == null ||
        initial.subscription == null) {
      throw StateError('initial subscribe failed: ${initial.error?.message}');
    }
    final events = initial.subscription!;
    subscription = events;
    final request = await rust.listPorts(handle: core);
    if (request.requestId == null) {
      throw StateError('list ports rejected: ${request.error?.message}');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var completed = false;
    while (DateTime.now().isBefore(deadline)) {
      final reply = await rust.nextEvent(subscription: events);
      if (reply.error != null) {
        throw StateError('event poll failed: ${reply.error!.message}');
      }
      final event = reply.event;
      if (event?.requestId == request.requestId) {
        if (event!.kind == rust.EventType.commandFailed) {
          throw StateError('port enumeration failed: ${event.error?.message}');
        }
        completed = event.kind == rust.EventType.commandCompleted;
        if (completed) break;
      }
    }
    if (!completed) {
      throw StateError('enumeration command completion not observed');
    }
    await rust.cancelSubscription(subscription: events);
    subscription = null;
    final resumed = await rust.subscribe(handle: core);
    if (resumed.error != null ||
        resumed.snapshot == null ||
        resumed.subscription == null) {
      throw StateError('resubscribe failed: ${resumed.error?.message}');
    }
    if (resumed.snapshot!.sequence < initial.snapshot!.sequence) {
      throw StateError('resubscribe snapshot sequence regressed');
    }
    subscription = resumed.subscription!;
    await rust.cancelSubscription(subscription: subscription);
    subscription = null;
    final closed = await rust.closeCore(handle: core);
    if (closed.error != null) {
      throw StateError('core close failed: ${closed.error!.message}');
    }
    final closeAgain = await rust.closeCore(handle: core);
    if (closeAgain.error != null) {
      throw StateError('idempotent close failed: ${closeAgain.error!.message}');
    }
    final rejected = await rust.listPorts(handle: core);
    if (rejected.error?.kind != rust.ErrorKind.closed) {
      throw StateError(
        'closed core accepted a command or returned an untyped error',
      );
    }
  } finally {
    if (subscription != null) {
      await rust.cancelSubscription(subscription: subscription);
    }
    if (handle != null) await rust.closeCore(handle: handle);
    await temp.delete(recursive: true);
  }
  if (resultPath != null) {
    await File(resultPath).writeAsString(sentinel, flush: true);
  }
  stdout.writeln(sentinel);
}

class CoreHostException implements Exception {
  final rust.CoreError error;
  const CoreHostException(this.error);
  @override
  String toString() =>
      '${error.kind.name}: ${error.message} (bytes written: ${error.bytesWritten})';
}
