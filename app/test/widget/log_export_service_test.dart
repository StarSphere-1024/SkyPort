import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/services/log_export_service.dart';

void main() {
  const channel = MethodChannel('skyport/android');

  for (final outcome in ['saved', 'cancelled', 'failed']) {
    testWidgets('Android log export $outcome cleans its temporary copy', (
      tester,
    ) async {
      String? temporaryPath;
      Future<void>? operation;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'exportFile');
        final arguments = Map<String, Object?>.from(call.arguments as Map);
        final path = arguments['path']! as String;
        expect(await File(path).readAsBytes(), [0, 13, 10, 255]);
        if (outcome == 'failed') {
          throw PlatformException(code: 'export_failed', message: 'Disk full');
        }
        return outcome == 'saved' ? 'content://documents/log.txt' : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  operation = LogExportService.exportLogs(
                    context: context,
                    defaultPath: '',
                    portName: 'USB/ESP32',
                    export: (path) async {
                      temporaryPath = path;
                      await File(path).writeAsBytes([0, 13, 10, 255]);
                    },
                  );
                },
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Export'));
        await operation;
      });
      await tester.pump();
      expect(temporaryPath, isNotNull);
      expect(File(temporaryPath!).parent.existsSync(), isFalse);
      final l10n = AppLocalizations.of(tester.element(find.text('Export')));
      if (outcome == 'saved') {
        expect(
          find.text('${l10n.logsExportedTo}content://documents/log.txt'),
          findsOneWidget,
        );
      } else if (outcome == 'cancelled') {
        expect(find.byType(SnackBar), findsNothing);
      } else {
        expect(
          find.text(l10n.exportFailed(l10n.errorPlatform)),
          findsOneWidget,
        );
      }
    });
  }
}
