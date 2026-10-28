import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/models/ui_state.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/widgets/right_panel/receive_display_widget.dart';

class ReceiveController extends UiController {
  @override
  UiState build() => UiState.fromSnapshot(
    const rust.AppSnapshot(
      sequence: 0,
      config: rust.AppConfig(
        version: 1,
        serial: rust.SerialConfig(
          portName: '',
          baudRate: 9600,
          dataBits: 8,
          parity: rust.Parity.none,
          flowControl: rust.FlowControl.none,
          stopBits: 1,
          autoReconnect: false,
        ),
        send: rust.SendSettings(
          hex: false,
          newline: rust.Newline.none,
          appendNewline: false,
          autoSendEnabled: false,
          autoSendIntervalMs: 1000,
        ),
        logCapacityBytes: 16777216,
        history: [],
      ),
      connection: rust.ConnectionState.connected,
      ports: [],
      rxBytes: 0,
      txBytes: 0,
      lastRxBytes: 0,
      rxBytesPerSecond: 0,
      log: rust.LogSnapshot(
        records: [],
        totalBytes: 0,
        trimmedBytes: 0,
        trimmedRecords: 0,
        incomplete: false,
      ),
      autoSendInput: '',
    ),
  );

  void resetLogs() => state = build();

  void receiveThrough(int last, {int? first, String Function(int)? textForId}) {
    state = state.withLogDelta(
      rust.LogDelta(
        upsert: [
          for (var id = first ?? last - 99; id <= last; id++)
            rust.LogRecord(
              id: id,
              timestampMs: 0,
              direction: rust.Direction.received,
              data: Uint8List.fromList(
                (textForId?.call(id) ?? 'row ${id.toString().padLeft(3, '0')}')
                    .codeUnits,
              ),
              pending: false,
            ),
        ],
        removedIds: const [],
        earliestId: first ?? last - 99,
        totalBytes: 700,
        trimmedBytes: (last - 100) * 7,
        trimmedRecords: last - 100,
        incomplete: false,
      ),
    );
  }
}

class ReceiveSettings extends UiSettingsNotifier {
  @override
  UiSettings build() => const UiSettings(showTimestamp: false, showSent: false);

  @override
  void setHexDisplay(bool value) => state = state.copyWith(hexDisplay: value);
}

void main() {
  testWidgets('toolbar remains usable without covering logs at narrow widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ReceiveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(() => controller),
          uiSettingsProvider.overrideWith(ReceiveSettings.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Column(children: [ReceiveDisplayWidget()])),
        ),
      ),
    );
    final buttons = find.byWidgetPredicate(
      (widget) =>
          widget is TextButton && widget.key != const ValueKey('search-open'),
    );
    for (final button in tester.widgetList<TextButton>(buttons)) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('search-open')))
          .onPressed,
      isNotNull,
    );
    controller.receiveThrough(101);
    await tester.pumpAndSettle();
    for (final button in tester.widgetList<TextButton>(buttons)) {
      expect(button.onPressed, isNotNull);
      expect(
        tester.getRect(find.byWidget(button)).bottom,
        lessThan(tester.getRect(find.byType(ListView)).top),
      );
    }
    final headerPosition = tester.getTopLeft(buttons.first);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(buttons.first), headerPosition);
    expect(tester.takeException(), isNull);
    controller.resetLogs();
    await tester.pumpAndSettle();
    for (final button in tester.widgetList<TextButton>(buttons)) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('search-open')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('toolbar actions stay reachable across widths and text scales', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in AppLocalizations.supportedLocales) {
      for (final scale in [1.0, 2.0]) {
        await tester.binding.setSurfaceSize(const Size(1100, 700));
        final controller = ReceiveController();
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              uiControllerProvider.overrideWith(() => controller),
              uiSettingsProvider.overrideWith(ReceiveSettings.new),
            ],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: Column(children: [ReceiveDisplayWidget()]),
              ),
            ),
          ),
        );
        controller.receiveThrough(2, first: 1);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ReceiveDisplayWidget)),
        );
        for (final width in [
          1100.0,
          696.0,
          481.8,
          480.0,
          320.0,
          240.0,
          160.0,
        ]) {
          await tester.binding.setSurfaceSize(Size(width, 700));
          await tester.pumpAndSettle();
          final panel = tester.getRect(find.byType(Card));
          final logs = tester.getRect(find.byType(ListView));
          for (final tooltip in [
            l10n.searchOpen,
            l10n.exportLogs,
            l10n.clearReceiveArea,
          ]) {
            final action = find.descendant(
              of: find.byTooltip(tooltip),
              matching: find.byType(TextButton),
            );
            expect(action.hitTestable(), findsOneWidget);
            final rect = tester.getRect(action);
            expect(rect.left, greaterThanOrEqualTo(panel.left));
            expect(rect.right, lessThanOrEqualTo(panel.right));
            expect(rect.bottom, lessThanOrEqualTo(logs.top));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          if (width == 1100 && scale == 1) {
            expect(find.text(l10n.exportLogs), findsOneWidget);
          } else if (width == 160) {
            expect(find.text(l10n.exportLogs), findsNothing);
          }
          if (width >= 320) {
            await tester.tap(find.byKey(const ValueKey('search-open')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('search-open')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('search-input')), findsNothing);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$locale, text scale $scale, width $width',
          );
        }
      }
    }
  });

  testWidgets('short output starts at the top and appends downward', (
    tester,
  ) async {
    final controller = ReceiveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(() => controller),
          uiSettingsProvider.overrideWith(ReceiveSettings.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Column(children: [ReceiveDisplayWidget()])),
        ),
      ),
    );
    controller.receiveThrough(2, first: 1);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byType(ListView)).dy;
    final row1 = tester
        .getTopLeft(find.textContaining('row 001', findRichText: true))
        .dy;
    final row2 = tester
        .getTopLeft(find.textContaining('row 002', findRichText: true))
        .dy;
    expect(row1, closeTo(top + 8, 1));
    expect(row2, greaterThan(row1));
  });

  testWidgets('return to latest reaches the end of variable-height output', (
    tester,
  ) async {
    final controller = ReceiveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(() => controller),
          uiSettingsProvider.overrideWith(ReceiveSettings.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Column(children: [ReceiveDisplayWidget()])),
        ),
      ),
    );
    controller.receiveThrough(100);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1600));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final readingPosition = position.pixels;
    String textForId(int id) => id > 80
        ? 'row $id ${List.filled(id % 7 + 1, 'wrapped data ' * 15).join('\n')}'
        : 'row $id';
    controller.receiveThrough(200, first: 1, textForId: textForId);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(readingPosition, 1));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(position.extentAfter, closeTo(0, 1));
    expect(find.byType(FloatingActionButton), findsNothing);
    final latest = find.textContaining('row 200 ', findRichText: true);
    expect(latest, findsOneWidget);
    expect(
      tester.getBottomRight(latest).dy,
      lessThanOrEqualTo(tester.getBottomRight(find.byType(ListView)).dy),
    );
    controller.receiveThrough(
      201,
      first: 1,
      textForId: (id) => id == 201 ? 'row 201' : textForId(id),
    );
    await tester.pumpAndSettle();
    expect(position.extentAfter, closeTo(0, 1));
    expect(find.textContaining('row 201', findRichText: true), findsOneWidget);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, -200),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.extentAfter, greaterThan(0));
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('variable-height follow never renders beyond the end', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(550, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ReceiveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiControllerProvider.overrideWith(() => controller),
          uiSettingsProvider.overrideWith(ReceiveSettings.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Column(children: [ReceiveDisplayWidget()])),
        ),
      ),
    );
    String text(int id) =>
        'row $id ${id % 30 < 15 ? 'wrapped MQTT data ' * 12 : 'short'}';
    for (var last = 150; last <= 185; last++) {
      controller.receiveThrough(last, first: 1, textForId: text);
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final position = tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        expect(
          position.pixels,
          inInclusiveRange(
            position.minScrollExtent - 1,
            position.maxScrollExtent + 1,
          ),
          reason: 'row $last, frame $frame must not overscroll and rebound',
        );
      }
      final latest = find.textContaining('row $last ', findRichText: true);
      expect(latest, findsOneWidget);
      expect(
        tester.getBottomRight(latest).dy,
        closeTo(tester.getBottomRight(find.byType(ListView)).dy - 8, 1),
      );
    }
  });

  testWidgets(
    'follow remains current at capacity and yields to user scrolling',
    (tester) async {
      final controller = ReceiveController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiControllerProvider.overrideWith(() => controller),
            uiSettingsProvider.overrideWith(ReceiveSettings.new),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Column(children: [ReceiveDisplayWidget()])),
          ),
        ),
      );
      controller.receiveThrough(100);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.extentAfter, closeTo(0, 1));

      controller.receiveThrough(101);
      controller.receiveThrough(102);
      await tester.pumpAndSettle();
      expect(position.extentAfter, closeTo(0, 1));
      expect(
        find.textContaining('row 102', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.textContaining('row 101', findRichText: true))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.textContaining('row 102', findRichText: true))
              .dy,
        ),
      );
      final settings = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveDisplayWidget)),
      ).read(uiSettingsProvider.notifier);
      settings.setHexDisplay(true);
      await tester.pumpAndSettle();
      expect(position.extentAfter, closeTo(0, 1));
      expect(
        find.textContaining('72 6F 77 20 31 30 32', findRichText: true),
        findsOneWidget,
      );
      settings.setHexDisplay(false);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pumpAndSettle();
      final readingPosition = position.pixels;
      expect(position.extentAfter, greaterThan(0));
      controller.receiveThrough(103);
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(readingPosition, 1));
      controller.resetLogs();
      await tester.pumpAndSettle();
      controller.receiveThrough(100);
      await tester.pumpAndSettle();
    },
  );
}
