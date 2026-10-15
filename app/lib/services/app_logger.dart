import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static final AppLogger instance = AppLogger();

  final File? _injectedFile;
  File? _file;
  bool _initialized = false;

  AppLogger({File? file}) : _injectedFile = file;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _file =
          _injectedFile ??
          File(
            '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}logs${Platform.pathSeparator}skyport.log',
          );
      await _file!.parent.create(recursive: true);
      if (!await _file!.exists()) {
        await _file!.create();
      }
      _initialized = true;
    } catch (error, stackTrace) {
      _emit(
        _LogLevel.error,
        'Failed to initialize application logger',
        name: 'skyport.logger',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void debug(String message, {String name = 'skyport'}) {
    _emit(_LogLevel.debug, message, name: name);
  }

  void info(String message, {String name = 'skyport'}) {
    _emit(_LogLevel.info, message, name: name);
  }

  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = 'skyport',
  }) {
    _emit(
      _LogLevel.warning,
      message,
      name: name,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = 'skyport',
  }) {
    _emit(
      _LogLevel.error,
      message,
      name: name,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _emit(
    _LogLevel level,
    String message, {
    required String name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: name,
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );

    if (kDebugMode) {
      debugPrint(
        '[$name] ${level.label}: $message'
        '${error == null ? '' : ' error=$error'}'
        '${stackTrace == null ? '' : ' stackTrace=$stackTrace'}',
      );
    }

    if (!_initialized || _file == null) return;

    final fields = <String>[
      'time=${DateTime.now().toIso8601String()}',
      'level=${level.label}',
      'name=$name',
      'message=$message',
      if (error != null) 'error=$error',
      if (stackTrace != null) 'stackTrace=$stackTrace',
    ];

    try {
      final handle = _file!.openSync(mode: FileMode.append);
      try {
        handle.writeFromSync(utf8.encode('${fields.join(' ')}\n'));
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
    } catch (writeError, writeStackTrace) {
      developer.log(
        'Failed to write application log',
        name: 'skyport.logger',
        level: _LogLevel.error.value,
        error: writeError,
        stackTrace: writeStackTrace,
      );
      if (kDebugMode) {
        debugPrint(
          '[skyport.logger] ERROR: Failed to write application log '
          'error=$writeError stackTrace=$writeStackTrace',
        );
      }
    }
  }
}

enum _LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warning(900, 'WARNING'),
  error(1000, 'ERROR');

  const _LogLevel(this.value, this.label);

  final int value;
  final String label;
}
