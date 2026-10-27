import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/host_core.dart';
import 'package:skyport/main.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/search_controller.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'package:skyport/src/rust/frb_generated.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }

  testWidgets(
    'native snapshot search rejects malformed Hex and closes with host',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('skyport-search-native-'),
      ))!;
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'ui_show_sent': true,
        'dynamic_color_enabled': false,
        'dynamic_color_preference_initialized': true,
      });
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
      const captureKey = ValueKey('search-smoke-capture');
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const RepaintBoundary(
              key: captureKey,
              child: SerialDebuggerApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-open')));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('search-input'));
        expect(input, findsOneWidget);
        await tester.enterText(input, 'not-present');
        await tester.pump();
        expect(container.read(searchControllerProvider).activeQuery, isNull);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _settleNative(tester, container);
        expect(
          container.read(searchControllerProvider).activeQuery,
          'not-present',
        );
        expect(container.read(searchControllerProvider).total, 0);
        expect(tester.takeException(), isNull);

        final search = (await tester.runAsync(
          () async => rust.startSearch(
            handle: bootstrap.handle,
            query: '中文😀',
            options: const rust.SearchOptions(
              hex: false,
              caseSensitive: true,
              showSent: true,
              stripAnsi: false,
            ),
          ),
        ))!;
        expect(search.error, isNull);
        expect(search.search, isNotNull);
        expect(search.snapshot, isNotNull);
        expect(search.snapshot!.firstRecordId, isNull);
        expect(search.snapshot!.lastRecordId, isNull);
        expect(search.snapshot!.pending, isNull);
        rust.SearchProgress? progress;
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          do {
            progress = await rust.pollSearch(search: search.search!);
            if (progress!.complete) break;
            if (DateTime.now().isAfter(deadline)) {
              fail('Native empty snapshot scan did not complete');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          } while (true);
        });
        expect(progress!.totalMatches, 0);
        expect(progress!.error, isNull);
        final absent = (await tester.runAsync(
          () => rust.searchMatch(search: search.search!, index: 0),
        ))!;
        expect(absent.hit, isNull);

        for (final query in ['0', 'GG']) {
          final rejected = (await tester.runAsync(
            () async => rust.startSearch(
              handle: bootstrap.handle,
              query: query,
              options: const rust.SearchOptions(
                hex: true,
                caseSensitive: true,
                showSent: true,
                stripAnsi: false,
              ),
            ),
          ))!;
          expect(rejected.search, isNull);
          expect(rejected.error?.kind, rust.ErrorKind.invalidArgument);
          expect(
            rejected.error?.code,
            query == '0'
                ? rust.ErrorCode.incompleteHexByte
                : rust.ErrorCode.invalidHexCharacter,
          );
        }
        final oversized = (await tester.runAsync(
          () async => rust.startSearch(
            handle: bootstrap.handle,
            query: '😀' * 16385,
            options: const rust.SearchOptions(
              hex: false,
              caseSensitive: true,
              showSent: true,
              stripAnsi: false,
            ),
          ),
        ))!;
        expect(oversized.search, isNull);
        expect(oversized.error?.code, rust.ErrorCode.searchQueryTooLarge);
        // Invalid submissions must not cancel the last accepted snapshot.
        final preserved = (await tester.runAsync(
          () => rust.pollSearch(search: search.search!),
        ))!;
        expect(preserved.cancelled, isFalse);
        await tester.runAsync(() => rust.cancelSearch(search: search.search!));
        final cancelled = (await tester.runAsync(
          () => rust.pollSearch(search: search.search!),
        ))!;
        expect(cancelled.cancelled, isTrue);

        await tester.tap(find.byKey(const ValueKey('search-submit')));
        await _settleNative(tester, container);
        await _capture(tester, captureKey, 'empty');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(input, findsNothing);
        await tester.tap(find.byKey(const ValueKey('search-open')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, 'not-present');
        await tester.tap(find.byKey(const ValueKey('search-open')));
        await tester.pumpAndSettle();
        expect(input, findsNothing);
        await tester.tap(find.byKey(const ValueKey('search-open')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, 'not-present');
        await tester.enterText(input, '');
        await tester.tap(find.byKey(const ValueKey('search-submit')));
        await _settleNative(tester, container);
        expect(container.read(searchControllerProvider).activeQuery, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        final closed = (await tester.runAsync(
          () => rust.closeCore(handle: bootstrap.handle),
        ))!;
        expect(closed.error, isNull);
        RustLib.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}

Future<void> _settleNative(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (container.read(searchControllerProvider).submitting ||
      !container.read(searchControllerProvider).complete) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native search UI did not settle');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  final output = Platform.environment['SKYPORT_SEARCH_SCREENSHOT'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await tester.runAsync(
      () => File('$output-$name.png').writeAsBytes(bytes!.buffer.asUint8List()),
    );
  } finally {
    image.dispose();
  }
}
