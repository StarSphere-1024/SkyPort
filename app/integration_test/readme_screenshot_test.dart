import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/main.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_controller.dart';

// Presentation fixture only: no CoreBootstrap, native session, or serial device.
class _ScreenshotController extends UiController {
  @override
  UiState build() {
    const lines = [
      '[DEMO] ANSI preview · no hardware required',
      'Received: ansi',
      'ANSI Escape Sequence Test',
      'Normal Text',
      '\x1b[1mBold Text\x1b[0m',
      '\x1b[3mItalic Text\x1b[0m',
      '\x1b[4mUnderlined Text\x1b[0m',
      '\x1b[1;3;4mBold + Italic + Underlined\x1b[0m',
      'Foreground Colors',
      '\x1b[31mRed\x1b[0m  \x1b[32mGreen\x1b[0m  \x1b[33mYellow\x1b[0m  \x1b[34mBlue\x1b[0m  \x1b[35mMagenta\x1b[0m  \x1b[36mCyan\x1b[0m  \x1b[37mWhite\x1b[0m',
      'Background Colors',
      '\x1b[30;41m Red \x1b[0m \x1b[30;42m Green \x1b[0m \x1b[30;43m Yellow \x1b[0m \x1b[30;44m Blue \x1b[0m \x1b[30;45m Magenta \x1b[0m \x1b[30;46m Cyan \x1b[0m',
      'Example Device Log (Demo)',
      '\x1b[32m[OK]\x1b[0m Serial link ready · 115200 baud · 8N1',
      '\x1b[36m[INFO]\x1b[0m Temperature: 24.6 °C | Humidity: 48.2 %',
      '\x1b[33m[WARN]\x1b[0m RX buffer usage: 72 %',
      '\x1b[31m[ERROR]\x1b[0m Example timeout · demonstration only',
      '\x1b[32m[OK]\x1b[0m All checks passed',
      'Progress: [####################] 100 %',
      '\x1b[32mDone!\x1b[0m',
    ];
    final timestamp = DateTime.utc(2026, 1, 1, 12);
    final entries = [
      LogEntry(
        Uint8List.fromList(utf8.encode('ansi')),
        LogEntryType.sent,
        timestamp,
        id: 1,
      ),
      for (var i = 0; i < lines.length; i++)
        LogEntry(
          Uint8List.fromList(utf8.encode(lines[i])),
          LogEntryType.received,
          timestamp.add(Duration(milliseconds: (i + 1) * 18)),
          id: i + 2,
        ),
    ];
    final rx = entries
        .skip(1)
        .fold<int>(0, (size, row) => size + row.data.length);
    return UiState(
      sequence: 0,
      connection: UiConnection.connected,
      portName: 'DEMO',
      baudRate: 115200,
      dataBits: 8,
      parity: UiParity.none,
      flowControl: UiFlowControl.none,
      stopBits: 1,
      autoReconnect: false,
      hexSend: false,
      newline: UiNewline.crlf,
      appendNewline: true,
      autoSendEnabled: false,
      autoSendIntervalMs: 1000,
      logCapacityBytes: 128 * 1024 * 1024,
      sendHistory: const ['ansi'],
      autoSendInput: 'ansi',
      ports: const ['DEMO'],
      rxBytes: rx,
      txBytes: 4,
      lastRxBytes: rx,
      error: null,
      logs: LogState(
        chunks: [LogChunk(entries: entries, id: 1)],
        totalBytes: rx + 4,
      ),
      trimmedBytes: 0,
      trimmedRecords: 0,
      logIncomplete: false,
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final work = env['SKYPORT_SCREENSHOT_DIR'];
  if (work != null && Platform.isWindows) {
    // Windows accessibility can enable platform semantics when foregrounded.
    // Establish that handle before testWidgets records its ownership baseline.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
  testWidgets(
    'render README demo fixture',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui_enable_ansi': true,
        'ui_show_timestamp': true,
        'ui_show_sent': true,
        'theme_mode': env['SKYPORT_SCREENSHOT_THEME']!,
        'dynamic_color_enabled': false,
        'dynamic_color_preference_initialized': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          uiControllerProvider.overrideWith(_ScreenshotController.new),
        ],
      );
      binding.platformDispatcher.localesTestValue = [
        Locale(env['SKYPORT_SCREENSHOT_LANGUAGE']!),
      ];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SerialDebuggerApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final pending = File('$work/window.pending');
          await pending.writeAsString(jsonEncode({'pid': pid}), flush: true);
          await pending.rename('$work/window.json');
        });
        await _wait(tester, () => File('$work/framed').existsSync());
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => File('$work/ready').writeAsString('ready', flush: true),
        );
        await _wait(tester, () => File('$work/captured').existsSync());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    },
    skip: work == null || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Screenshot script did not acknowledge the rendered frame');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
