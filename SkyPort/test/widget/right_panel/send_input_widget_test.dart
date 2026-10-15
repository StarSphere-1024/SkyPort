import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/widgets/right_panel/send_input_widget.dart';

class FakeUiController extends UiController {
  FakeUiController(this.initialState);
  final UiState initialState;
  final sent = <String>[];

  @override
  UiState build() => initialState;

  @override
  Future<void> send(String value) async => sent.add(value);

  @override
  Future<void> setAutoSendInput(String input) async {}

  void simulateDisconnect() =>
      state = sendState(connection: UiConnection.disconnected);
  void updateMode(bool hex, String input) => state = sendState(
    connection: UiConnection.connected,
    hex: hex,
    input: input,
  );
}

UiState sendState({
  required UiConnection connection,
  bool hex = false,
  List<String> history = const [],
  String input = '',
}) => UiState(
  sequence: 0,
  connection: connection,
  portName: '',
  baudRate: 9600,
  dataBits: 8,
  parity: UiParity.none,
  stopBits: 1,
  autoReconnect: true,
  hexSend: hex,
  newline: UiNewline.none,
  autoSendEnabled: false,
  autoSendIntervalMs: 1000,
  logCapacityBytes: 128 * 1024 * 1024,
  sendHistory: history,
  autoSendInput: input,
  ports: const [],
  rxBytes: 0,
  txBytes: 0,
  lastRxBytes: 0,
  error: null,
  logs: const LogState(),
  trimmedBytes: 0,
  trimmedRecords: 0,
  logIncomplete: false,
);

Widget app(FakeUiController controller) => ProviderScope(
  overrides: [uiControllerProvider.overrideWith(() => controller)],
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SendInputWidget()),
  ),
);

void main() {
  testWidgets(
    'history navigation restores the unsent draft and respects multiline cursor boundaries',
    (tester) async {
      await tester.pumpWidget(
        app(
          FakeUiController(
            sendState(
              connection: UiConnection.connected,
              history: ['one', 'two'],
            ),
          ),
        ),
      );
      final input = find.byType(TextFormField);
      await tester.enterText(input, 'draft');
      await tester.pump();
      Future<void> key(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }

      String text() => tester.widget<TextFormField>(input).controller!.text;
      await key(LogicalKeyboardKey.arrowUp);
      expect(text(), 'two');
      await key(LogicalKeyboardKey.arrowUp);
      expect(text(), 'one');
      await key(LogicalKeyboardKey.arrowUp);
      expect(text(), 'one');
      await key(LogicalKeyboardKey.arrowDown);
      expect(text(), 'two');
      await key(LogicalKeyboardKey.arrowDown);
      expect(text(), 'draft');
      await tester.enterText(input, 'first\nsecond');
      tester.widget<TextFormField>(input).controller!.selection =
          const TextSelection.collapsed(offset: 12);
      await tester.pump();
      expect(text(), 'first\nsecond');
      await key(LogicalKeyboardKey.arrowUp);
      expect(text(), 'first\nsecond');
      tester.widget<TextFormField>(input).controller!.selection =
          const TextSelection.collapsed(offset: 0);
      await key(LogicalKeyboardKey.arrowDown);
      expect(text(), 'first\nsecond');
      await tester.enterText(input, 'edited');
      await key(LogicalKeyboardKey.arrowUp);
      await tester.enterText(input, 'replacement');
      await key(LogicalKeyboardKey.arrowUp);
      expect(text(), 'two');
      await key(LogicalKeyboardKey.arrowDown);
      expect(text(), 'replacement');
    },
  );

  testWidgets(
    'draft mode conversion is UTF-8 exact and never pads invalid Hex or replaces binary bytes',
    (tester) async {
      await tester.pumpWidget(
        app(FakeUiController(sendState(connection: UiConnection.connected))),
      );
      var container = ProviderScope.containerOf(
        tester.element(find.byType(SendInputWidget)),
      );
      var draft = container.read(autoSendDraftProvider.notifier);
      draft.setDraft('中\u0000');
      expect(draft.forMode(true), 'E4 B8 AD 00');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          FakeUiController(
            sendState(connection: UiConnection.connected, hex: true),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(SendInputWidget)),
      );
      draft = container.read(autoSendDraftProvider.notifier);
      draft.setDraft('E4 B8 AD 00');
      expect(draft.forMode(false), '中\u0000');
      for (final input in ['A', '41\u00A042', 'FF FE']) {
        draft.setDraft(input);
        expect(draft.forMode(false), input);
      }
    },
  );
  testWidgets(
    'committed mode changes replace the visible codec atomically without losing the draft',
    (tester) async {
      final controller = FakeUiController(
        sendState(connection: UiConnection.connected),
      );
      await tester.pumpWidget(app(controller));
      final input = find.byType(TextFormField);
      await tester.enterText(input, '中');
      await tester.pump();
      controller.updateMode(true, 'E4 B8 AD');
      await tester.pump();
      expect(tester.widget<TextFormField>(input).controller!.text, 'E4 B8 AD');
      controller.updateMode(false, '中');
      await tester.pump();
      expect(tester.widget<TextFormField>(input).controller!.text, '中');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tester.widget<TextFormField>(input).controller!.text, '中');
    },
  );
  testWidgets('validates hex input at the UI intent boundary', (tester) async {
    await tester.pumpWidget(
      app(
        FakeUiController(
          sendState(connection: UiConnection.connected, hex: true),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'ABC');
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), ' \t\n');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), '0G');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), 'AB CD');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('disconnect disables a nonempty draft without discarding it', (
    tester,
  ) async {
    final controller = FakeUiController(
      sendState(connection: UiConnection.connected),
    );
    await tester.pumpWidget(app(controller));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), 'hello');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    controller.simulateDisconnect();
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'hello',
    );
  });
}
