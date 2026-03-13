// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skyport/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const SerialDebuggerApp(),
      ),
    );

    // Verify that the app title is displayed
    expect(find.text('SkyPort'), findsOneWidget);
  });
}
