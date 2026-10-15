import 'dart:typed_data';

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

  void receiveThrough(int last) {
    state = state.withLogDelta(
      rust.LogDelta(
        upsert: [
          for (var id = last - 99; id <= last; id++)
            rust.LogRecord(
              id: id,
              timestampMs: 0,
              direction: rust.Direction.received,
              data: Uint8List.fromList(
                'row ${id.toString().padLeft(3, '0')}'.codeUnits,
              ),
              pending: false,
            ),
        ],
        removedIds: const [],
        earliestId: last - 99,
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
      expect(position.extentBefore, closeTo(0, 1));

      controller.receiveThrough(101);
      controller.receiveThrough(102);
      await tester.pumpAndSettle();
      expect(position.extentBefore, closeTo(0, 1));
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
      expect(position.extentBefore, closeTo(0, 1));
      expect(
        find.textContaining('72 6F 77 20 31 30 32', findRichText: true),
        findsOneWidget,
      );
      settings.setHexDisplay(false);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pumpAndSettle();
      final readingPosition = position.pixels;
      expect(position.extentBefore, greaterThan(0));
      controller.receiveThrough(103);
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(readingPosition, 1));
    },
  );
}
