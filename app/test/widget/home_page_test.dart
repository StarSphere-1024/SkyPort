import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/main.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/widgets/left_panel.dart';
import 'package:skyport/widgets/application_settings.dart';
import 'package:skyport/widgets/connection_rail.dart';
import 'package:skyport/widgets/status_bar.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';

class LayoutController extends UiController {
  String portName = '/dev/serial/by-id/usb-very-long-device-name-1234567890';
  UiState snapshot(UiConnection connection) => UiState(
    sequence: 0,
    connection: connection,
    portName: portName,
    baudRate: 115200,
    dataBits: 8,
    parity: UiParity.none,
    flowControl: UiFlowControl.none,
    stopBits: 1,
    autoReconnect: false,
    hexSend: false,
    newline: UiNewline.none,
    autoSendEnabled: false,
    autoSendIntervalMs: 1000,
    logCapacityBytes: 128 * 1024 * 1024,
    sendHistory: const [],
    autoSendInput: '',
    ports: [if (portName.isNotEmpty) portName],
    rxBytes: 123456789,
    txBytes: 987654321,
    rxBytesPerSecond: 1536.5,
    lastRxBytes: 123456,
    error: null,
    logs: const LogState(),
    trimmedBytes: 0,
    trimmedRecords: 0,
    logIncomplete: false,
  );

  @override
  UiState build() => snapshot(UiConnection.connected);

  @override
  Future<void> disconnect() async =>
      state = snapshot(UiConnection.disconnected);

  @override
  Future<void> connect() async => state = snapshot(UiConnection.connected);

  void showConnection(UiConnection connection) => state = snapshot(connection);
  UiConnection get connection => state.connection;

  void showPort(String value) {
    portName = value;
    state = snapshot(state.connection);
  }
}

void main() {
  testWidgets('panel visibility survives page recreation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    Future<void> mount() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await prefs.reload();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiControllerProvider.overrideWith(LayoutController.new),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
    final expand = find.byWidgetPredicate(
      (widget) => widget is ConnectionRail && !widget.panelOpen,
    );
    final collapse = find.byWidgetPredicate(
      (widget) => widget is ConnectionRail && widget.panelOpen,
    );
    expect(collapse, findsOneWidget);

    await mount();
    expect(collapse, findsOneWidget);
    expect(find.byType(LeftPanel).hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.serialPageLabel));
    await tester.pumpAndSettle();
    await mount();
    expect(expand, findsOneWidget);
    expect(find.byType(LeftPanel).hitTestable(), findsNothing);

    await tester.tap(find.byTooltip(l10n.settingsPageLabel));
    await tester.pumpAndSettle();
    await mount();
    expect(collapse, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await mount();
    expect(expand, findsOneWidget);
  });

  testWidgets(
    'bottom connection control and drawer preserve drafts across viewports',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiControllerProvider.overrideWith(LayoutController.new),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomePage(),
          ),
        ),
      );
      final input = find.descendant(
        of: find.byType(SendInputWidget),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(input, 'unsent draft');
      final textController = tester.widget<TextFormField>(input).controller!;
      textController.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
      final rail = find.byType(ConnectionRail);
      final portPage = find.descendant(
        of: rail,
        matching: find.text(l10n.serialPageLabel),
      );
      final settingsPage = find.byTooltip(l10n.settingsPageLabel);
      final power = find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(IconButton),
      );
      final send = find.descendant(
        of: find.byType(SendInputWidget),
        matching: find.byType(FilledButton),
      );
      final controller =
          ProviderScope.containerOf(
                tester.element(find.byType(HomePage)),
              ).read(uiControllerProvider.notifier)
              as LayoutController;
      await tester.tap(power);
      await tester.pumpAndSettle();
      expect(controller.connection, UiConnection.disconnected);
      expect(tester.widget<ConnectionRail>(rail).panelOpen, isTrue);
      await tester.tap(power);
      await tester.pumpAndSettle();
      expect(controller.connection, UiConnection.connected);
      expect(tester.widget<ConnectionRail>(rail).panelOpen, isTrue);
      await tester.tap(settingsPage);
      await tester.pumpAndSettle();
      final buffer = find.descendant(
        of: find.byType(ApplicationSettings),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(buffer);
      await tester.enterText(buffer, '25');
      await tester.pump();
      await tester.tap(settingsPage);
      await tester.pumpAndSettle();
      expect(tester.widget<ConnectionRail>(rail).panelOpen, isFalse);
      expect(buffer.hitTestable(), findsNothing);
      await tester.tap(settingsPage);
      await tester.pumpAndSettle();
      expect(find.byType(ApplicationSettings), findsOneWidget);
      expect(tester.widget<TextFormField>(buffer).controller!.text, '25');

      tester
          .widget<TextField>(
            find.descendant(of: input, matching: find.byType(TextField)),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      tester.view.physicalSize = const Size(320, 480);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<ConnectionRail>(rail).panelOpen, isFalse);

      for (final size in [
        const Size(320, 480),
        const Size(574, 1387),
        const Size(799, 640),
        const Size(800, 700),
        const Size(1000, 700),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.tap(portPage);
        await tester.pumpAndSettle();
        expect(find.byType(LeftPanel), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, l10n.disconnect));
        await tester.pumpAndSettle();
        expect(controller.connection, UiConnection.disconnected);
        await tester.tap(find.widgetWithText(FilledButton, l10n.connect));
        await tester.pumpAndSettle();
        expect(controller.connection, UiConnection.connected);
        expect(power.hitTestable(), findsOneWidget);
        final baudMenu = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<int> && widget.initialSelection == 115200,
        );
        final baudInput = find.descendant(
          of: baudMenu,
          matching: find.byType(EditableText),
        );
        final baudText = tester
            .state<EditableTextState>(baudInput)
            .renderEditable;
        final textLayout = TextPainter(
          text: baudText.text,
          textDirection: baudText.textDirection,
          textScaler: baudText.textScaler,
          maxLines: 1,
        )..layout();
        expect(textLayout.width, lessThanOrEqualTo(baudText.size.width));
        textLayout.dispose();
        final panelRect = tester.getRect(find.byType(LeftPanel));
        final baudRect = tester.getRect(baudMenu);
        final flowRect = tester.getRect(
          find.byType(DropdownMenu<UiFlowControl>),
        );
        expect(baudRect.left, greaterThanOrEqualTo(panelRect.left));
        expect(flowRect.right, lessThanOrEqualTo(panelRect.right));
        expect(flowRect.top, baudRect.top);
        expect(flowRect.height, baudRect.height);
        expect(flowRect.left, greaterThan(baudRect.right));
        await tester.tap(portPage);
        await tester.pumpAndSettle();
        expect(tester.widget<ConnectionRail>(rail).panelOpen, isFalse);
        expect(find.byType(LeftPanel).hitTestable(), findsNothing);
        await tester.tap(portPage);
        await tester.pumpAndSettle();
        expect(tester.widget<ConnectionRail>(rail).panelOpen, isTrue);
        expect(tester.takeException(), isNull);

        if (size.width == 799) {
          await tester.tapAt(const Offset(780, 150));
          await tester.pumpAndSettle();
          expect(tester.widget<ConnectionRail>(rail).panelOpen, isTrue);
        }
        await tester.tap(power);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(send).onPressed, isNull);
        await tester.tap(power);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.widget<ConnectionRail>(rail).panelOpen, isFalse);
        expect(
          tester.widget<TextFormField>(input).controller,
          same(textController),
        );
        expect(textController.text, 'unsent draft');
        expect(textController.selection.baseOffset, 3);
        await tester.tap(settingsPage);
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(buffer).controller!.text, '25');
      }

      tester.view.physicalSize = const Size(720, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(power.hitTestable(), findsOneWidget);

      for (final connection in [
        UiConnection.connecting,
        UiConnection.reconfiguring,
        UiConnection.disconnecting,
        UiConnection.closing,
        UiConnection.closed,
      ]) {
        controller.showConnection(connection);
        await tester.pump();
        expect(tester.widget<IconButton>(power).onPressed, isNull);
      }
      controller.showConnection(UiConnection.reconnecting);
      await tester.pump();
      await tester.tap(power);
      await tester.pumpAndSettle();
      expect(controller.connection, UiConnection.disconnected);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      controller.showPort('');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(power).onPressed, isNull);
      expect(controller.connection, UiConnection.disconnected);
    },
  );
  testWidgets('connection status indicator stays legible across brightness', (
    tester,
  ) async {
    double contrast(Color foreground, Color background) {
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [uiControllerProvider.overrideWith(LayoutController.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light(useMaterial3: true),
          home: const StatusBar(),
        ),
      ),
    );
    expect(find.textContaining('115200 · 8N1'), findsOneWidget);
    expect(find.textContaining('1.5 KiB/s'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final statusText = tester.widget<Text>(
      find
          .descendant(of: find.byType(StatusBar), matching: find.byType(Text))
          .first,
    );
    expect(statusText.maxLines, 1);
    expect(statusText.overflow, TextOverflow.ellipsis);
    var theme = Theme.of(tester.element(find.byType(StatusBar)));
    var status = tester.widget<Icon>(find.byIcon(Icons.circle)).color!;
    expect(
      contrast(status, theme.colorScheme.surface),
      greaterThanOrEqualTo(3),
    );
    final lightController =
        ProviderScope.containerOf(
              tester.element(find.byType(StatusBar)),
            ).read(uiControllerProvider.notifier)
            as LayoutController;
    lightController.showConnection(UiConnection.reconfiguring);
    await tester.pump();
    status = tester.widget<Icon>(find.byIcon(Icons.circle)).color!;
    expect(
      contrast(status, theme.colorScheme.surface),
      greaterThanOrEqualTo(3),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [uiControllerProvider.overrideWith(LayoutController.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(useMaterial3: true),
          home: const StatusBar(),
        ),
      ),
    );
    theme = Theme.of(tester.element(find.byType(StatusBar)));
    status = tester.widget<Icon>(find.byIcon(Icons.circle)).color!;
    expect(
      contrast(status, theme.colorScheme.surface),
      greaterThanOrEqualTo(3),
    );
    final darkController =
        ProviderScope.containerOf(
              tester.element(find.byType(StatusBar)),
            ).read(uiControllerProvider.notifier)
            as LayoutController;
    darkController.showConnection(UiConnection.reconfiguring);
    await tester.pump();
    status = tester.widget<Icon>(find.byIcon(Icons.circle)).color!;
    expect(
      contrast(status, theme.colorScheme.surface),
      greaterThanOrEqualTo(3),
    );
  });
}
