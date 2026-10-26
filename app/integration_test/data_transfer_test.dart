import 'dart:convert';
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
import 'package:skyport/providers/theme_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/src/rust/frb_generated.dart';
import 'package:skyport/utils/error_messages.dart';
import 'package:skyport/widgets/connection_rail.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';
import 'package:skyport/widgets/application_settings.dart';
import 'package:skyport/widgets/left_panel/send_settings_widget.dart';
import 'package:skyport/widgets/left_panel/serial_params_widget.dart';
import 'package:skyport/widgets/status_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final hasPtyHarness =
      Platform.environment['SKYPORT_PTY'] != null &&
      Platform.environment['SKYPORT_PTY_CONTROL'] != null &&
      Platform.environment['SKYPORT_PTY_ACK'] != null;

  testWidgets('application settings persist reconnect changes', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('skyport-settings-'),
    ))!;
    SharedPreferences.setMockInitialValues({'serial_auto_reconnect': false});
    final prefs = await SharedPreferences.getInstance();
    final bootstrap = (await tester.runAsync(
      () => createCoreFromHost(prefs, dataDirectory: directory.path),
    ))!;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        coreBootstrapProvider.overrideWithValue(bootstrap),
      ],
    );
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SerialDebuggerApp(),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
      await tester.tap(find.byTooltip(l10n.settingsPageLabel));
      await tester.pumpAndSettle();
      final reconnect = find.byKey(const ValueKey('auto-reconnect-switch'));
      for (final enabled in [true, false]) {
        await tester.ensureVisible(reconnect);
        await tester.tap(reconnect);
        await _until(
          tester,
          () => container.read(uiControllerProvider).autoReconnect == enabled,
        );
        final saved = await tester.runAsync(
          () async =>
              jsonDecode(
                    await File('${directory.path}/config.json').readAsString(),
                  )
                  as Map<String, dynamic>,
        );
        expect(saved!['serial']['auto_reconnect'], enabled);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      final closed = await tester.runAsync(
        () => rust.closeCore(handle: bootstrap.handle),
      );
      expect(closed!.error, isNull);
      RustLib.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });

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
      'theme_mode': 'system',
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
      await _until(
        tester,
        () => container!.read(uiControllerProvider).rxBytesPerSecond > 0,
      );
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.textContaining('B/s'),
        ),
        findsOneWidget,
      );
      await _until(
        tester,
        () => container!.read(uiControllerProvider).rxBytesPerSecond == 0,
      );
      expect(find.textContaining('0 B/s'), findsOneWidget);
      final retainedLogBytes = state.logs.chunks
          .expand((chunk) => chunk.entries)
          .map((row) => row.data)
          .toList();
      final controller = container.read(uiControllerProvider.notifier);
      const draft = 'unsent theme draft';
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.enterText(input, draft);
      await tester.pump();
      final inputController = tester.widget<TextField>(input).controller!;
      expect(inputController.text, draft);
      await tester.tap(find.byTooltip(l10n.settingsPageLabel));
      await tester.pumpAndSettle();
      final capacityInput = find.descendant(
        of: find.byType(ApplicationSettings),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(capacityInput);
      await tester.enterText(capacityInput, '256');
      await tester.pump();
      final exportPath = '${directory.path}/before-theme.txt';
      final exportBefore = await tester.runAsync(() async {
        // The raw bridge reply only acknowledges enqueueing, not file creation.
        await controller.exportLog(
          exportPath,
          const rust.ExportOptions(
            showSent: true,
            hex: false,
            timestamps: true,
            stripAnsi: false,
          ),
        );
        return File(exportPath).readAsBytes();
      });
      final exportedBefore = exportBefore!;
      final capacity = tester.widget<TextFormField>(capacityInput).controller!;
      final expectedLogCapacity = state.logCapacityBytes;
      expect(expectedLogCapacity, 128 * 1024 * 1024);
      expect(capacity.text, '256');
      expect(inputController.text, draft);
      for (final seed in [Colors.red, const Color(0xffab34ef)]) {
        container.read(themeColorProvider.notifier).setThemeColor(seed);
        container.read(themeModeProvider.notifier).toggleTheme();
        await tester.pumpAndSettle();
        state = container.read(uiControllerProvider);
        expect(
          identical(controller, container.read(uiControllerProvider.notifier)),
          isTrue,
        );
        expect(state.connection, UiConnection.connected);
        expect(state.rxBytes, 5);
        expect(state.txBytes, 5);
        expect(
          state.logs.chunks
              .expand((chunk) => chunk.entries)
              .map((row) => row.data)
              .toList(),
          retainedLogBytes,
        );
      }
      expect(inputController.text, draft);
      expect(capacity.text, '256');
      expect(
        container.read(uiControllerProvider).logCapacityBytes,
        expectedLogCapacity,
      );
      final exportAfter = await tester.runAsync(() async {
        await controller.exportLog(
          '${directory.path}/after-theme.txt',
          const rust.ExportOptions(
            showSent: true,
            hex: false,
            timestamps: true,
            stripAnsi: false,
          ),
        );
        return File('${directory.path}/after-theme.txt').readAsBytes();
      });
      expect(exportAfter, exportedBefore);

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
      if (find.byType(SerialParamsWidget).hitTestable().evaluate().isEmpty) {
        await tester.tap(
          find.descendant(
            of: find.byType(ConnectionRail),
            matching: find.text(l10n.serialPageLabel),
          ),
        );
        await tester.pumpAndSettle();
      }

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
        await tester.tap(
          find.descendant(of: flowMenu, matching: find.byType(EditableText)),
        );
        await tester.pumpAndSettle();
        final currentLocalizations = AppLocalizations.of(
          tester.element(find.byType(HomePage)),
        );
        final label = switch (uiMode) {
          UiFlowControl.none => currentLocalizations.flowControlNone,
          UiFlowControl.hardware => currentLocalizations.flowControlHardware,
          UiFlowControl.software => currentLocalizations.flowControlSoftware,
        };
        await tester.tap(find.widgetWithText(MenuItemButton, label));
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
          await tester.tap(
            find.descendant(
              of: restoredMenu,
              matching: find.byType(EditableText),
            ),
          );
          await tester.pumpAndSettle();
          final selection = switch (uiMode) {
            UiFlowControl.none => strings.flowControlNone,
            UiFlowControl.hardware => strings.flowControlHardware,
            UiFlowControl.software => strings.flowControlSoftware,
          };
          await tester.tap(find.widgetWithText(MenuItemButton, selection));
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

      final reconnectController = container!.read(
        uiControllerProvider.notifier,
      );
      reconnectController.setAutoReconnect(true);
      await _until(
        tester,
        () => container!.read(uiControllerProvider).autoReconnect,
      );
      final strings = AppLocalizations.of(
        tester.element(find.byType(HomePage)),
      );
      if (tester
          .widget<ConnectionRail>(find.byType(ConnectionRail))
          .panelOpen) {
        await tester.tap(find.byTooltip(strings.serialPageLabel));
        await tester.pumpAndSettle();
      }
      final retrySubscription = (await tester.runAsync(
        () => rust.subscribe(handle: handle),
      ))!;
      await tester.runAsync(() => _ptyControl('unplug1'));
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).connection ==
            UiConnection.reconnecting,
      );
      final reconnectingNotice = strings.disconnectedReconnecting;
      final noticeText = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(SelectableText),
      );
      expect(
        tester.widget<SelectableText>(noticeText).data,
        reconnectingNotice,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3500)),
      );
      await tester.pumpAndSettle();
      final attempts = (await tester.runAsync(
        () => rust.nextEvents(subscription: retrySubscription.subscription!),
      ))!;
      expect(
        attempts.events.where(
          (event) => event.kind == rust.EventType.reconnecting,
        ),
        hasLength(greaterThanOrEqualTo(6)),
      );
      await tester.runAsync(
        () => rust.cancelSubscription(
          subscription: retrySubscription.subscription!,
        ),
      );
      expect(
        container.read(uiControllerProvider).connection,
        UiConnection.reconnecting,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.textContaining(strings.reconnecting),
        ),
        findsOneWidget,
      );
      final diagnostic = container.read(uiControllerProvider).error!;
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(SelectableText),
              ),
            )
            .data,
        contains(diagnostic.message),
      );
      await tester.tap(find.widgetWithText(TextButton, strings.close));
      await tester.pumpAndSettle();

      await tester.runAsync(() => _ptyControl('replace'));
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).connection ==
            UiConnection.connected,
      );
      expect(container.read(uiControllerProvider).error, isNull);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await tester.runAsync(() => _ptyControl('unplug2'));
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).connection ==
            UiConnection.reconnecting,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.circle),
          matching: find.byType(IconButton),
        ),
      );
      await _until(
        tester,
        () =>
            container!.read(uiControllerProvider).connection ==
            UiConnection.disconnected,
      );
      // Clear the second loss notice before checking the manual failure.
      ScaffoldMessenger.of(
        tester.element(find.byType(HomePage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)),
      );
      expect(
        container.read(uiControllerProvider).connection,
        UiConnection.disconnected,
      );
      expect(container.read(uiControllerProvider).error, isNull);
      await tester.runAsync(() => reconnectController.connect());
      await _until(
        tester,
        () => container!.read(uiControllerProvider).error != null,
      );
      expect(
        container.read(uiControllerProvider).connection,
        UiConnection.disconnected,
      );
      expect(
        tester.widget<SelectableText>(noticeText).data,
        localizedError(strings, container.read(uiControllerProvider).error!),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      final closed = await tester.runAsync(
        () => rust.closeCore(handle: handle),
      );
      expect(closed!.error, isNull);
      RustLib.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  }, skip: !hasPtyHarness);
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
  await tester.pump();
}

Future<void> _ptyControl(String command) async {
  final control = File(Platform.environment['SKYPORT_PTY_CONTROL']!);
  final acknowledgement = File(Platform.environment['SKYPORT_PTY_ACK']!);
  await control.writeAsString(command, flush: true);
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await acknowledgement.exists() ||
      await acknowledgement.readAsString() != command) {
    if (DateTime.now().isAfter(deadline)) {
      fail('PTY harness did not acknowledge $command');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
