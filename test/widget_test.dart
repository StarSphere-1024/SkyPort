// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_port/main.dart';

void main() {
  testWidgets('App title localized (English default)',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SerialDebuggerApp());

    // The app bar title should be SkyPort (English locale fallback)
    expect(find.text('SkyPort'), findsOneWidget);
  });
}
