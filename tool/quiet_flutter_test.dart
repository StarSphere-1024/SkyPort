import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultFlutterPath = '/home/star/env/flutter/bin/flutter';
const _maxBufferedPrintsPerTest = 20;
const _maxBufferedRawLines = 120;

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }

  final flutterBin = Platform.environment['FLUTTER_BIN'] ?? _defaultFlutterPath;
  final forwardedArgs = _sanitizeArgs(args);
  final command = [flutterBin, 'test', '--machine', ...forwardedArgs];
  final startedAt = DateTime.now();

  stdout.writeln('Running: ${_shellJoin(command)}');

  final process = await Process.start(
    flutterBin,
    ['test', '--machine', ...forwardedArgs],
    workingDirectory: Directory.current.path,
    runInShell: false,
  );

  final reporter = _QuietTestReporter();

  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(reporter.handleStdoutLine)
      .asFuture<void>();

  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(reporter.handleStderrLine)
      .asFuture<void>();

  final processExitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);

  final elapsed = DateTime.now().difference(startedAt);
  final effectiveExitCode = reporter.hasFailures ? 1 : processExitCode;
  reporter.printSummary(elapsed, effectiveExitCode);

  exitCode = effectiveExitCode;
}

List<String> _sanitizeArgs(List<String> args) {
  return [
    for (final arg in args)
      if (arg != '--machine' &&
          arg != '--reporter=expanded' &&
          arg != '--reporter=compact')
        arg,
  ];
}

void _printUsage() {
  stdout.writeln('''
Run Flutter tests with quiet output.

Usage:
  dart tool/quiet_flutter_test.dart [flutter test args]

Examples:
  dart tool/quiet_flutter_test.dart
  dart tool/quiet_flutter_test.dart test/ansi_test.dart
  dart tool/quiet_flutter_test.dart --name "shows mode"

Environment:
  FLUTTER_BIN  Override Flutter binary. Default: $_defaultFlutterPath
''');
}

String _shellJoin(List<String> parts) {
  return parts.map(_shellQuote).join(' ');
}

String _shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

class _QuietTestReporter {
  final Map<int, String> _testNamesById = {};
  final Map<int, List<String>> _printsByTestId = {};
  final List<_Failure> _failures = [];
  final List<String> _rawLines = [];
  final List<String> _stderrLines = [];

  int _passed = 0;
  int _failed = 0;
  int _skipped = 0;

  bool get hasFailures => _failures.isNotEmpty || _failed > 0;

  void handleStdoutLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _appendBounded(_rawLines, line, _maxBufferedRawLines);
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      _appendBounded(_rawLines, line, _maxBufferedRawLines);
      return;
    }

    _handleEvent(decoded);
  }

  void handleStderrLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    _appendBounded(_stderrLines, line, _maxBufferedRawLines);
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'testStart':
        final id = event['testID'];
        final test = event['test'];
        if (id is int && test is Map<String, dynamic>) {
          final name = test['name'];
          if (name is String) {
            _testNamesById[id] = name;
          }
        }
      case 'print':
        final id = event['testID'];
        final message = event['message'];
        if (id is int && message is String) {
          final lines = _printsByTestId.putIfAbsent(id, () => <String>[]);
          _appendBounded(lines, message, _maxBufferedPrintsPerTest);
        }
      case 'error':
        final id = event['testID'];
        final error = event['error'];
        final stackTrace = event['stackTrace'];
        _failures.add(
          _Failure(
            testName: id is int
                ? _testNamesById[id] ?? _fallbackNameFromStackTrace(stackTrace)
                : _fallbackNameFromStackTrace(stackTrace),
            error: error is String ? error : event.toString(),
            stackTrace: stackTrace is String ? stackTrace : null,
            prints:
                id is int ? List.of(_printsByTestId[id] ?? const []) : const [],
          ),
        );
      case 'testDone':
        final result = event['result'];
        if (result == 'success') {
          _passed += 1;
        } else if (result == 'skipped') {
          _skipped += 1;
        } else if (result == 'failure' || result == 'error') {
          _failed += 1;
        }
    }
  }

  void printSummary(Duration elapsed, int exitCode) {
    final total = _passed + _failed + _skipped;
    if (_failures.isEmpty && exitCode == 0) {
      stdout.writeln(
        'PASS $total tests in ${_formatDuration(elapsed)}'
        '${_skipped > 0 ? ' ($_skipped skipped)' : ''}.',
      );
      return;
    }

    stdout.writeln('');
    stdout.writeln(
      'FAIL $_failed/$total tests in ${_formatDuration(elapsed)}'
      '${_skipped > 0 ? ' ($_skipped skipped)' : ''}.',
    );

    for (var index = 0; index < _failures.length; index += 1) {
      final failure = _failures[index];
      stdout.writeln('');
      stdout.writeln(
        'Failure ${index + 1}: ${failure.testName ?? 'unknown test'}',
      );
      if (failure.prints.isNotEmpty) {
        stdout.writeln('Recent test output:');
        for (final line in failure.prints) {
          stdout.writeln('  $line');
        }
      }
      stdout.writeln(failure.error.trimRight());
      final stackTrace = failure.stackTrace?.trimRight();
      if (stackTrace != null && stackTrace.isNotEmpty) {
        stdout.writeln(stackTrace);
      }
    }

    if (_stderrLines.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('stderr tail:');
      for (final line in _stderrLines) {
        stdout.writeln(line);
      }
    }

    if (_failures.isEmpty && _rawLines.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('raw output tail:');
      for (final line in _rawLines) {
        stdout.writeln(line);
      }
    }
  }

  void _appendBounded(List<String> target, String line, int maxLength) {
    target.add(line);
    if (target.length > maxLength) {
      target.removeRange(0, target.length - maxLength);
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  }

  String? _fallbackNameFromStackTrace(Object? stackTrace) {
    if (stackTrace is! String) {
      return null;
    }
    final match = RegExp(
      r'^(test/[^:\s]+\.dart(?::\d+:\d+|\s+\d+:\d+))',
      multiLine: true,
    ).firstMatch(stackTrace);
    return match?.group(1);
  }
}

class _Failure {
  final String? testName;
  final String error;
  final String? stackTrace;
  final List<String> prints;

  const _Failure({
    required this.testName,
    required this.error,
    required this.stackTrace,
    required this.prints,
  });
}
