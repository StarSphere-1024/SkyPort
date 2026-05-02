import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/models/serial_config.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/widgets/left_panel/serial_params_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_data.dart';

void main() {
  group('SerialParamsWidget', () {
    late MockSerialPortService mockService;
    late FakeSharedPreferences fakePrefs;

    setUpAll(registerFallbackValues);

    setUp(() {
      mockService = MockSerialPortService();
      fakePrefs = FakeSharedPreferences()
        ..setString('serial_port_name', 'COM1')
        ..setInt('serial_baud_rate', 9600)
        ..setInt('serial_data_bits', 8)
        ..setInt('serial_parity', 0)
        ..setInt('serial_stop_bits', 1);
      setupMockSerialPortService(mockService);
      when(() => mockService.getAvailablePorts())
          .thenAnswer((_) async => ['COM1']);
    });

    Widget createTestWidget({SerialConfig? config}) {
      if (config != null) {
        fakePrefs
          ..setString('serial_port_name', config.portName)
          ..setInt('serial_baud_rate', config.baudRate)
          ..setInt('serial_data_bits', config.dataBits)
          ..setInt('serial_parity', config.parity)
          ..setInt('serial_stop_bits', config.stopBits)
          ..setBool('serial_auto_reconnect', config.autoReconnect);
      }

      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(fakePrefs),
          serialPortServiceProvider.overrideWithValue(mockService),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en', 'US'),
          home: Scaffold(
            body: SerialParamsWidget(),
          ),
        ),
      );
    }

    testWidgets('renders dropdowns and labels', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(DropdownMenu<int>), findsWidgets);
      expect(find.text('Baud Rate'), findsOneWidget);
      expect(find.text('Data Bits'), findsOneWidget);
      expect(find.text('Parity'), findsOneWidget);
      expect(find.text('Stop Bits'), findsOneWidget);
    });

    testWidgets('contains standard baud rates', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final dropdowns = tester.widgetList<DropdownMenu<int>>(
        find.byType(DropdownMenu<int>),
      );

      final baudDropdown = dropdowns.first;
      expect(baudDropdown.dropdownMenuEntries.length, 11);
      final labels =
          baudDropdown.dropdownMenuEntries.map((e) => e.label).toList();
      expect(labels, containsAll(['1200', '9600', '115200', '921600']));
    });

    testWidgets('displays custom config values', (tester) async {
      final customConfig = SerialConfig(
        portName: 'COM1',
        baudRate: 115200,
        dataBits: 7,
        parity: 1,
        stopBits: 2,
        autoReconnect: false,
      );

      await tester.pumpWidget(createTestWidget(config: customConfig));
      await tester.pumpAndSettle();

      expect(find.text('115200'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Odd'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(createTestWidget(config: defaultSerialConfig()));
      await tester.pumpAndSettle();

      expect(find.byType(SerialParamsWidget), findsOneWidget);
    });
  });
}
