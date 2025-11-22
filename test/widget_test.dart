// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sky_port/main.dart';
import 'package:sky_port/providers/serial_provider.dart';
import 'package:sky_port/services/serial_port_service.dart';

void main() {
  testWidgets('App title localized (English default)',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // 避免测试环境加载原生串口 DLL，提供空端口列表与空服务
        availablePortsProvider
            .overrideWith((ref) => Stream<List<String>>.value(<String>[])),
        serialPortServiceProvider.overrideWithValue(_MockSerialPortService()),
        serialConnectionProvider
            .overrideWith(_DummySerialConnectionNotifier.new),
        serialConfigProvider.overrideWith(_DummySerialConfigNotifier.new),
      ],
      child: const SerialDebuggerApp(),
    ));

    // The app bar title should be SkyPort (English locale fallback)
    expect(find.text('SkyPort'), findsOneWidget);
  });
}

// 简单的 Mock，避免真正的串口操作
class _MockSerialPortService extends SerialPortService {}

class _DummySerialConfigNotifier extends SerialConfigNotifier {
  @override
  SerialConfig? build() => null;
}

class _DummySerialConnectionNotifier extends SerialConnectionNotifier {
  @override
  SerialConnection build() => SerialConnection();

  @override
  Future<void> disconnect() async {}
}
