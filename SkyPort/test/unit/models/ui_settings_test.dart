import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/ui_settings.dart';

void main() {
  group('UiSettings', () {
    group('Default Values', () {
      test('hexDisplay defaults to false', () {
        const settings = UiSettings();
        expect(settings.hexDisplay, false);
      });

      test('hexSend defaults to false', () {
        const settings = UiSettings();
        expect(settings.hexSend, false);
      });

      test('showTimestamp defaults to true', () {
        const settings = UiSettings();
        expect(settings.showTimestamp, true);
      });

      test('showSent defaults to true', () {
        const settings = UiSettings();
        expect(settings.showSent, true);
      });

      test('blockIntervalMs defaults to 20', () {
        const settings = UiSettings();
        expect(settings.blockIntervalMs, 20);
      });

      test('receiveMode defaults to block', () {
        const settings = UiSettings();
        expect(settings.receiveMode, ReceiveMode.block);
      });

      test('preferredReceiveMode defaults to line', () {
        const settings = UiSettings();
        expect(settings.preferredReceiveMode, ReceiveMode.line);
      });

      test('appendNewline defaults to false', () {
        const settings = UiSettings();
        expect(settings.appendNewline, false);
      });

      test('newlineMode defaults to lf', () {
        const settings = UiSettings();
        expect(settings.newlineMode, NewlineMode.lf);
      });

      test('enableAnsi defaults to false', () {
        const settings = UiSettings();
        expect(settings.enableAnsi, false);
      });

      test('logBufferSize defaults to 128', () {
        const settings = UiSettings();
        expect(settings.logBufferSize, 128);
      });

      test('autoSendEnabled defaults to false', () {
        const settings = UiSettings();
        expect(settings.autoSendEnabled, false);
      });

      test('autoSendIntervalMs defaults to 1000', () {
        const settings = UiSettings();
        expect(settings.autoSendIntervalMs, 1000);
      });
    });

    group('copyWith', () {
      test('updates hexDisplay while keeping other values', () {
        const original = UiSettings(
          hexDisplay: false,
          hexSend: false,
          showTimestamp: true,
          showSent: true,
          blockIntervalMs: 20,
          receiveMode: ReceiveMode.block,
          preferredReceiveMode: ReceiveMode.line,
          appendNewline: false,
          newlineMode: NewlineMode.lf,
          enableAnsi: false,
          logBufferSize: 128,
          autoSendEnabled: false,
          autoSendIntervalMs: 1000,
        );

        final updated = original.copyWith(hexDisplay: true);

        expect(updated.hexDisplay, true);
        expect(updated.hexSend, false); // unchanged
        expect(updated.showTimestamp, true); // unchanged
        expect(updated.enableAnsi, false); // unchanged
      });

      test('updates all boolean flags', () {
        const original = UiSettings();

        final updated = original.copyWith(
          hexDisplay: true,
          hexSend: true,
          showTimestamp: false,
          showSent: false,
          appendNewline: true,
          enableAnsi: true,
          autoSendEnabled: true,
        );

        expect(updated.hexDisplay, true);
        expect(updated.hexSend, true);
        expect(updated.showTimestamp, false);
        expect(updated.showSent, false);
        expect(updated.appendNewline, true);
        expect(updated.enableAnsi, true);
        expect(updated.autoSendEnabled, true);
      });

      test('updates blockIntervalMs', () {
        const original = UiSettings(blockIntervalMs: 20);
        final updated = original.copyWith(blockIntervalMs: 50);

        expect(updated.blockIntervalMs, 50);
      });

      test('updates receiveMode', () {
        const original = UiSettings(receiveMode: ReceiveMode.block);
        final updated = original.copyWith(receiveMode: ReceiveMode.line);

        expect(updated.receiveMode, ReceiveMode.line);
      });

      test('updates preferredReceiveMode', () {
        const original = UiSettings(preferredReceiveMode: ReceiveMode.line);
        final updated =
            original.copyWith(preferredReceiveMode: ReceiveMode.block);

        expect(updated.preferredReceiveMode, ReceiveMode.block);
      });

      test('updates newlineMode', () {
        const original = UiSettings(newlineMode: NewlineMode.lf);
        final updated = original.copyWith(newlineMode: NewlineMode.crlf);

        expect(updated.newlineMode, NewlineMode.crlf);
      });

      test('updates logBufferSize', () {
        const original = UiSettings(logBufferSize: 128);
        final updated = original.copyWith(logBufferSize: 256);

        expect(updated.logBufferSize, 256);
      });

      test('updates autoSendIntervalMs', () {
        const original = UiSettings(autoSendIntervalMs: 1000);
        final updated = original.copyWith(autoSendIntervalMs: 500);

        expect(updated.autoSendIntervalMs, 500);
      });

      test('updates all fields at once', () {
        const original = UiSettings();

        final updated = original.copyWith(
          hexDisplay: true,
          hexSend: true,
          showTimestamp: false,
          showSent: false,
          blockIntervalMs: 100,
          receiveMode: ReceiveMode.line,
          preferredReceiveMode: ReceiveMode.block,
          appendNewline: true,
          newlineMode: NewlineMode.crlf,
          enableAnsi: true,
          logBufferSize: 512,
          autoSendEnabled: true,
          autoSendIntervalMs: 2000,
        );

        expect(updated.hexDisplay, true);
        expect(updated.hexSend, true);
        expect(updated.showTimestamp, false);
        expect(updated.showSent, false);
        expect(updated.blockIntervalMs, 100);
        expect(updated.receiveMode, ReceiveMode.line);
        expect(updated.preferredReceiveMode, ReceiveMode.block);
        expect(updated.appendNewline, true);
        expect(updated.newlineMode, NewlineMode.crlf);
        expect(updated.enableAnsi, true);
        expect(updated.logBufferSize, 512);
        expect(updated.autoSendEnabled, true);
        expect(updated.autoSendIntervalMs, 2000);
      });

      test('creates independent copy - modifying copy does not affect original',
          () {
        const original = UiSettings(hexDisplay: false, logBufferSize: 128);
        final copy = original.copyWith(
          hexDisplay: true,
          logBufferSize: 256,
        );

        expect(original.hexDisplay, false); // unchanged
        expect(original.logBufferSize, 128); // unchanged
        expect(copy.hexDisplay, true); // modified
        expect(copy.logBufferSize, 256); // modified
      });
    });
  });
}
