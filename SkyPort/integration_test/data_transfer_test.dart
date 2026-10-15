import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/host_core.dart';
import 'package:skyport/main.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/widgets/right_panel/send_input_widget.dart';
import 'package:skyport/widgets/left_panel/send_settings_widget.dart';
import 'package:skyport/widgets/left_panel/port_selection_widget.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real bridge preserves bytes and survives UI disposal', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('skyport-ui-pty-'),
    ))!;
    SharedPreferences.setMockInitialValues({
      'serial_port_name': Platform.environment['SKYPORT_PTY']!,
      'serial_auto_reconnect': false,
      'ui_append_newline': true,
      'ui_newline_mode': 2,
    });
    final prefs = await SharedPreferences.getInstance();
    final bootstrap = await tester.runAsync(
      () => createCoreFromHost(prefs, dataDirectory: directory.path),
    );
    final handle = bootstrap!.handle;
    ProviderContainer? container;
    try {
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          coreBootstrapProvider.overrideWithValue(bootstrap),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SerialDebuggerApp(),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(PortSelectionWidget),
          matching: find.byType(FilledButton),
        ),
      );
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).connection ==
            UiConnection.connected,
      );

      final input = find.descendant(
        of: find.byType(SendInputWidget),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'PTY');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await _until(
        tester,
        () => container!.read(uiControllerProvider).rxBytes == 5,
      );
      var state = container.read(uiControllerProvider);
      expect(state.txBytes, 5);
      expect(
        state.logs.chunks
            .expand((chunk) => chunk.entries)
            .where((row) => row.type == LogEntryType.received)
            .single
            .data,
        [0, 0xff, 0xfe],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = null;
      final afterDispose = await tester.runAsync(
        () => rust.snapshot(handle: handle),
      );
      expect(afterDispose!.error, isNull);
      expect(afterDispose.snapshot!.connection, rust.ConnectionState.connected);

      final sent = await tester.runAsync(
        () => rust.sendHex(handle: handle, input: '00 ff A5 0a'),
      );
      expect(sent!.error, isNull);
      final fresh = await tester.runAsync(() => rust.subscribe(handle: handle));
      expect(fresh!.error, isNull);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          coreBootstrapProvider.overrideWithValue(
            CoreBootstrap(handle, fresh.snapshot!, fresh.subscription!),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SerialDebuggerApp(),
        ),
      );
      await _until(tester, () {
        final current = container!.read(uiControllerProvider);
        return current.txBytes == 9 &&
            current.sendHistory.isNotEmpty &&
            current.sendHistory.last == '00 ff A5 0a';
      });
      state = container.read(uiControllerProvider);
      expect(state.rxBytes, 5);
      expect(state.sendHistory.last, '00 ff A5 0a');

      final hexSwitch = find
          .descendant(
            of: find.byType(SendSettingsWidget),
            matching: find.byType(Switch),
          )
          .first;
      await tester.tap(hexSwitch);
      await _until(tester, () => container!.read(uiControllerProvider).hexSend);
      await tester.enterText(input, '41 42');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await _until(
        tester,
        () => container!.read(uiControllerProvider).txBytes == 11,
      );
      await tester.tap(hexSwitch);
      await _until(
        tester,
        () => !container!.read(uiControllerProvider).hexSend,
      );
      expect(tester.widget<TextField>(input).controller!.text, 'AB');
      await tester.tap(find.byIcon(Icons.send));
      await _until(
        tester,
        () => container!.read(uiControllerProvider).txBytes == 15,
      );

      // Saturate an actual bounded subscription while no UI consumes it.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = null;
      final beforeOverflow = (await tester.runAsync(
        () => rust.subscribe(handle: handle),
      ))!;
      await tester.runAsync(() async {
        final payload = 'Q' * (512 * 1024);
        for (var index = 0; index < 50; index++) {
          final accepted = await rust.updateConfig(
            handle: handle,
            patch: rust.ConfigPatch(autoSendInput: '$payload$index'),
          );
          expect(accepted.error, isNull);
        }
        await rust.updateConfig(
          handle: handle,
          patch: const rust.ConfigPatch(autoSendInput: 'AB'),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((await rust.snapshot(handle: handle)).snapshot!.autoSendInput !=
            'AB') {
          if (DateTime.now().isAfter(deadline)) {
            fail('core did not drain queued input patches');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          coreBootstrapProvider.overrideWithValue(
            CoreBootstrap(
              handle,
              beforeOverflow.snapshot!,
              beforeOverflow.subscription!,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SerialDebuggerApp(),
        ),
      );
      await _until(tester, () {
        final current = container!.read(uiControllerProvider);
        return current.dataGap && current.error == null;
      });
      expect(container.read(uiControllerProvider).txBytes, 15);
      expect(container.read(uiControllerProvider).rxBytes, 5);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).txBytes == 0 &&
            !container.read(uiControllerProvider).dataGap,
      );
      state = container.read(uiControllerProvider);
      expect(state.rxBytes, 0);
      expect(state.logs.chunks, isEmpty);
      expect(state.dataGap, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      final closed = await tester.runAsync(
        () => rust.closeCore(handle: handle),
      );
      expect(closed!.error, isNull);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  }, skip: Platform.environment['SKYPORT_PTY'] == null);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('native UI state did not reach the expected transition');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}
