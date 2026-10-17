import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/host_core.dart';
import 'package:skyport/main.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/widgets/connection_rail.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';
import 'package:skyport/widgets/left_panel/send_settings_widget.dart';
import 'package:skyport/widgets/left_panel/serial_params_widget.dart';
import 'package:skyport/widgets/status_bar.dart';

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
    var handle = bootstrap!.handle;
    ProviderContainer? container;
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
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
      final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
      final power = find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(IconButton),
      );
      await tester.tap(power);
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
      await tester.tap(
        find.descendant(
          of: find.byType(ConnectionRail),
          matching: find.text(l10n.serialPageLabel),
        ),
      );
      await tester.pumpAndSettle();

      // Exercise every driver mode through the real UI and bridge.
      final flowMenu = find.descendant(
        of: find.byType(SerialParamsWidget),
        matching: find.byType(DropdownMenu<UiFlowControl>),
      );
      for (final (uiMode, coreMode) in [
        (UiFlowControl.hardware, rust.FlowControl.hardware),
        (UiFlowControl.software, rust.FlowControl.software),
        (UiFlowControl.none, rust.FlowControl.none),
      ]) {
        await tester.ensureVisible(flowMenu);
        await tester.tap(flowMenu);
        await tester.pumpAndSettle();
        final label = switch (uiMode) {
          UiFlowControl.none => l10n.flowControlNone,
          UiFlowControl.hardware => l10n.flowControlHardware,
          UiFlowControl.software => l10n.flowControlSoftware,
        };
        await tester.tap(find.text(label).last);
        await _until(
          tester,
          () =>
              container!.read(uiControllerProvider).flowControl == uiMode &&
              container.read(uiControllerProvider).connection ==
                  UiConnection.connected,
        );
        final applied = await tester.runAsync(
          () => rust.snapshot(handle: handle),
        );
        expect(applied!.snapshot!.config.serial.flowControl, coreMode);
      }

      final hexSwitch = find
          .descendant(
            of: find.byType(SendSettingsWidget),
            matching: find.byType(Switch),
          )
          .first;
      await tester.ensureVisible(hexSwitch);
      await tester.tap(hexSwitch);
      await _until(tester, () => container!.read(uiControllerProvider).hexSend);
      await tester.enterText(input, '41 42');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await _until(
        tester,
        () => container!.read(uiControllerProvider).txBytes == 11,
      );
      await tester.ensureVisible(hexSwitch);
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

      // Drain bursts without losing command outcomes or inventing sequence gaps.
      await tester.runAsync(() async {
        final controller = container!.read(uiControllerProvider.notifier);
        await Future.wait([
          for (var index = 0; index < 48; index++)
            controller.setAutoSendInput('batch $index'),
        ]);
        await controller.setAutoSendInput('AB');
      });
      state = container.read(uiControllerProvider);
      expect(state.autoSendInput, 'AB');
      expect(state.error, isNull);
      expect(state.dataGap, isFalse);

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
      await tester.tap(find.byTooltip(l10n.clearReceiveArea));
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

      // Persist every selection through a real core shutdown/recreation, then
      // render and connect from the restored configuration in both locales.
      tester.view.physicalSize = const Size(574, 1387);
      addTearDown(tester.view.resetPhysicalSize);
      for (final language in ['en', 'zh']) {
        tester.binding.platformDispatcher.localesTestValue = [Locale(language)];
        await tester.pumpAndSettle();
        final localizedStrings = AppLocalizations.of(
          tester.element(find.byType(HomePage)),
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byType(DropdownMenu<UiFlowControl>),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          localizedStrings.flowControlNone,
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byType(DropdownMenu<UiParity>),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          localizedStrings.parityNone,
        );
        for (final (uiMode, coreMode) in [
          (UiFlowControl.hardware, rust.FlowControl.hardware),
          (UiFlowControl.software, rust.FlowControl.software),
          (UiFlowControl.none, rust.FlowControl.none),
        ]) {
          if (find.byType(SerialParamsWidget).evaluate().isEmpty) {
            final strings = AppLocalizations.of(
              tester.element(find.byType(HomePage)),
            );
            await tester.tap(
              find.descendant(
                of: find.byType(ConnectionRail),
                matching: find.text(strings.serialPageLabel),
              ),
            );
            await tester.pumpAndSettle();
          }
          final strings = AppLocalizations.of(
            tester.element(find.byType(HomePage)),
          );
          expect(strings.localeName, language);
          final restoredMenu = find.byType(DropdownMenu<UiFlowControl>);
          await tester.ensureVisible(restoredMenu);
          await tester.tap(restoredMenu);
          await tester.pumpAndSettle();
          final selection = switch (uiMode) {
            UiFlowControl.none => strings.flowControlNone,
            UiFlowControl.hardware => strings.flowControlHardware,
            UiFlowControl.software => strings.flowControlSoftware,
          };
          await tester.tap(find.text(selection).last);
          await _until(
            tester,
            () => container!.read(uiControllerProvider).flowControl == uiMode,
          );
          expect(container!.read(uiControllerProvider).error, isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          container = null;
          expect(
            (await tester.runAsync(
              () => rust.closeCore(handle: handle),
            ))!.error,
            isNull,
          );
          final reopened = (await tester.runAsync(
            () => rust.createCore(dataDirectory: directory.path),
          ))!;
          expect(reopened.error, isNull);
          handle = reopened.handle!;
          final subscription = (await tester.runAsync(
            () => rust.subscribe(handle: handle),
          ))!;
          expect(subscription.error, isNull);
          expect(subscription.snapshot!.config.serial.flowControl, coreMode);
          container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              coreBootstrapProvider.overrideWithValue(
                CoreBootstrap(
                  handle,
                  subscription.snapshot!,
                  subscription.subscription!,
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
          await tester.pumpAndSettle();
          expect(container.read(uiControllerProvider).flowControl, uiMode);
          expect(
            tester
                .widget<DropdownMenu<UiFlowControl>>(restoredMenu)
                .initialSelection,
            uiMode,
          );
          await tester.runAsync(
            () => container!.read(uiControllerProvider.notifier).connect(),
          );
          await _until(
            tester,
            () =>
                container!.read(uiControllerProvider).connection ==
                UiConnection.connected,
          );
          final restored = (await tester.runAsync(
            () => rust.snapshot(handle: handle),
          ))!;
          expect(restored.snapshot!.appliedConfig!.flowControl, coreMode);
        }
      }
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
