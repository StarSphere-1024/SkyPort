import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/services/app_logger.dart';

void main() {
  late Directory tempDirectory;
  late File logFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('skyport_logger_');
    logFile = File('${tempDirectory.path}/skyport.log');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('writes error details and warning context in order', () async {
    final logger = AppLogger(file: logFile);
    await logger.initialize();
    final stackTrace = StackTrace.fromString('test stack trace');

    logger.error(
      'write failed',
      name: 'skyport.serial',
      error: StateError('broken'),
      stackTrace: stackTrace,
    );
    logger.warning(
      'port unavailable',
      name: 'skyport.serial',
      error: Exception('offline'),
      stackTrace: stackTrace,
    );

    final contents = await logFile.readAsString();
    expect(contents, contains('level=ERROR'));
    expect(contents, contains('name=skyport.serial message=write failed'));
    expect(contents, contains('error=Bad state: broken'));
    expect(contents, contains('stackTrace=test stack trace'));
    expect(contents, contains('level=WARNING'));
    expect(contents, contains('name=skyport.serial message=port unavailable'));
    expect(contents.indexOf('message=write failed'),
        lessThan(contents.indexOf('message=port unavailable')));
  });
}
