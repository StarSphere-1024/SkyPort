import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sky_port/l10n/app_localizations.dart';
import 'package:sky_port/widgets/right_panel.dart';
import 'package:sky_port/providers/serial_provider.dart';
import 'package:sky_port/services/serial_port_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RightPanel hides sent entries when showSent is false',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        availablePortsProvider
            .overrideWith((ref) => Stream<List<String>>.value(<String>[])),
        serialPortServiceProvider.overrideWithValue(_MockSerialPortService()),
        serialConnectionProvider
            .overrideWith(_DummySerialConnectionNotifier.new),
        serialConfigProvider.overrideWith(_DummySerialConfigNotifier.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RightPanel()),
      ),
    ));

    // Access container via context
    final context = tester.element(find.byType(RightPanel));
    final container = ProviderScope.containerOf(context);

    // Add one sent and one received entry
    container
        .read(dataLogProvider.notifier)
        .addSent(Uint8List.fromList([0x41])); // 'A'
    container
        .read(dataLogProvider.notifier)
        .addReceived(Uint8List.fromList([0x42])); // 'B'

    // Disable showing sent data
    container.read(uiSettingsProvider.notifier).setShowSent(false);

    await tester.pumpAndSettle();

    // 期望：不显示方向指示符，只显示接收内容 'B'
    expect(find.textContaining('RX <'), findsNothing);
    expect(find.textContaining('TX >'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });
}

class _MockSerialPortService extends SerialPortService {}

class _DummySerialConfigNotifier extends SerialConfigNotifier {
  @override
  SerialConfig? build() => null;
}

class _DummySerialConnectionNotifier extends SerialConnectionNotifier {
  @override
  SerialConnection build() => SerialConnection();

  @override
  Future<void> disconnect() async {
    // no-op to avoid Riverpod restrictions during dispose in tests
  }
}
