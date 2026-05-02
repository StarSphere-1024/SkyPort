import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skyport/l10n/app_localizations.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/providers/serial/serial_port_manager.dart';
import 'package:skyport/widgets/left_panel/port_selection_widget.dart';

import '../../helpers/mock_classes.dart';

void main() {
  group('PortSelectionWidget', () {
    late MockSerialPortService mockService;
    late FakeSharedPreferences fakePrefs;

    setUpAll(registerFallbackValues);

    setUp(() {
      mockService = MockSerialPortService();
      fakePrefs = FakeSharedPreferences()
        ..setString('serial_port_name', 'COM1');
      setupMockSerialPortService(mockService);
    });

    Widget createTestWidget({
      List<String> availablePorts = const ['COM1', 'COM2', 'COM3'],
    }) {
      when(() => mockService.getAvailablePorts())
          .thenAnswer((_) async => availablePorts);

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
            body: PortSelectionWidget(),
          ),
        ),
      );
    }

    testWidgets('renders dropdown and button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(DropdownMenu<String>), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('shows no ports found when list is empty', (tester) async {
      fakePrefs.clear();
      await tester.pumpWidget(createTestWidget(availablePorts: const []));
      await tester.pumpAndSettle();

      expect(find.text('No ports found'), findsOneWidget);
    });

    testWidgets('shows unavailable error for missing selected port',
        (tester) async {
      fakePrefs.setString('serial_port_name', 'COM9');

      await tester.pumpWidget(
        createTestWidget(availablePorts: const ['COM1', 'COM2']),
      );
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownMenu<String>>(
        find.byType(DropdownMenu<String>),
      );
      expect(dropdown.errorText, isNotNull);
    });
  });
}
