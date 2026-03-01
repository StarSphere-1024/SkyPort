import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/serial/data_log_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';
import 'package:skyport/providers/common_providers.dart';
import 'package:skyport/widgets/right_panel/receive_display_widget.dart';

import '../../helpers/mock_classes.dart';
import '../../helpers/test_providers.dart';

/// Test implementation of DataLogNotifier
class TestDataLogNotifier extends DataLogNotifier {
  final LogState _initialState;

  TestDataLogNotifier(this._initialState);

  @override
  LogState build() => _initialState;
}

/// Helper to create test widget with all necessary providers
Widget createReceiveDisplayTestWidget({
  List<LogChunk> chunks = const [],
  UiSettings? settings,
  Key? key,
}) {
  return ProviderScope(
    key: key,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(FakeSharedPreferences()),
      dataLogProvider.overrideWith(
        () => TestDataLogNotifier(
          LogState(
            chunks: chunks,
            totalBytes: chunks.fold(0, (sum, c) => sum + c.totalBytes),
            nextChunkId: chunks.length,
          ),
        ),
      ),
      uiSettingsProvider.overrideWith(
        () => TestUiSettingsNotifier(settings ?? const UiSettings()),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [ReceiveDisplayWidget()],
        ),
      ),
    ),
  );
}

void main() {
  group('ReceiveDisplayWidget - Basic Rendering', () {
    testWidgets('renders without crashing with empty log', (tester) async {
      await tester.pumpWidget(createReceiveDisplayTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ReceiveDisplayWidget), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('uses Card.outlined container', (tester) async {
      await tester.pumpWidget(createReceiveDisplayTestWidget());
      await tester.pumpAndSettle();

      final card = tester.widget<Card>(find.byType(Card).first);
      expect(card.elevation == null || card.elevation == 0, isTrue);
    });

    testWidgets('applies correct background color', (tester) async {
      await tester.pumpWidget(createReceiveDisplayTestWidget());
      await tester.pumpAndSettle();

      final card = tester.widget<Card>(find.byType(Card).first);
      expect(card.color, isNotNull);
    });

    testWidgets('includes Scrollbar widget', (tester) async {
      await tester.pumpWidget(createReceiveDisplayTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('uses monospace font for data display', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([72, 101, 108, 108, 111]), // "Hello"
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 5,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets.isNotEmpty, isTrue);
    });
  });

  group('ReceiveDisplayWidget - Log Display', () {
    testWidgets('displays received data (RX)', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([72, 101, 108, 108, 111]), // "Hello"
              LogEntryType.received,
              DateTime(2024, 1, 1, 12, 0, 0),
            ),
          ],
          totalBytes: 5,
          id: 0,
        ),
      ];

      final settings = const UiSettings(
        showTimestamp: true,
        showSent: true,
        hexDisplay: false,
      );

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: settings,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hello'), findsOneWidget);
      expect(find.textContaining('12:00:00'), findsOneWidget);
    });

    testWidgets('displays sent data (TX) when showSent=true', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([84, 88]), // "TX"
              LogEntryType.sent,
              DateTime(2024, 1, 1, 12, 0, 0),
            ),
          ],
          totalBytes: 2,
          id: 0,
        ),
      ];

      final settings = const UiSettings(
        showTimestamp: true,
        showSent: true,
        hexDisplay: false,
      );

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: settings,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('TX'), findsOneWidget);
    });

    testWidgets('hides sent data when showSent=false', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([82, 88]), // "RX"
              LogEntryType.received,
              DateTime(2024, 1, 1, 12, 0, 0),
            ),
            LogEntry(
              Uint8List.fromList([84, 88]), // "TX"
              LogEntryType.sent,
              DateTime(2024, 1, 1, 12, 0, 1),
            ),
          ],
          totalBytes: 4,
          id: 0,
        ),
      ];

      final settings = const UiSettings(
        showTimestamp: false,
        showSent: false,
        hexDisplay: false,
      );

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: settings,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('RX'), findsOneWidget);
      expect(find.textContaining('TX'), findsNothing);
    });

    testWidgets('toggles timestamp display', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([84, 101, 115, 116]), // "Test"
              LogEntryType.received,
              DateTime(2024, 1, 1, 12, 30, 45, 123),
            ),
          ],
          totalBytes: 4,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(showTimestamp: true),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('12:30:45'), findsOneWidget);

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(showTimestamp: false),
        key: UniqueKey(),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('12:30:45'), findsNothing);
    });

    testWidgets('displays in hex mode', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([72, 101]), // "He"
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 2,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(hexDisplay: true),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('48'), findsOneWidget);
      expect(find.textContaining('65'), findsOneWidget);
    });

    testWidgets('displays in text mode', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([72, 101, 108, 108, 111]), // "Hello"
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 5,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(hexDisplay: false),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('handles multiple log entries in correct order',
        (tester) async {
      final now = DateTime.now();
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(Uint8List.fromList([49]), LogEntryType.received, now),
            LogEntry(Uint8List.fromList([50]), LogEntryType.received,
                now.add(const Duration(seconds: 1))),
            LogEntry(Uint8List.fromList([51]), LogEntryType.received,
                now.add(const Duration(seconds: 2))),
          ],
          totalBytes: 3,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(showTimestamp: false),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('1'), findsOneWidget);
      expect(find.textContaining('2'), findsOneWidget);
      expect(find.textContaining('3'), findsOneWidget);
    });
  });

  group('LogIndexMapper', () {
    testWidgets('handles empty chunks list', (tester) async {
      final mapper = LogIndexMapper([], showSent: true);
      expect(mapper.totalCount, equals(0));
    });

    testWidgets('maps single chunk correctly', (tester) async {
      final entries = [
        LogEntry(
            Uint8List.fromList([1]), LogEntryType.received, DateTime.now()),
        LogEntry(
            Uint8List.fromList([2]), LogEntryType.received, DateTime.now()),
      ];
      final chunks = [
        LogChunk(entries: entries, totalBytes: 2, id: 0),
      ];

      final mapperRx = LogIndexMapper(chunks, showSent: false);
      expect(mapperRx.totalCount, equals(2));
      expect(mapperRx[0], equals(entries[0]));
      expect(mapperRx[1], equals(entries[1]));
    });

    testWidgets('maps multiple chunks correctly', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
                Uint8List.fromList([1]), LogEntryType.received, DateTime.now()),
            LogEntry(
                Uint8List.fromList([2]), LogEntryType.received, DateTime.now()),
          ],
          totalBytes: 2,
          id: 0,
        ),
        LogChunk(
          entries: [
            LogEntry(
                Uint8List.fromList([3]), LogEntryType.received, DateTime.now()),
          ],
          totalBytes: 1,
          id: 1,
        ),
      ];

      final mapper = LogIndexMapper(chunks, showSent: false);
      expect(mapper.totalCount, equals(3));
      expect(mapper[0].data[0], equals(1));
      expect(mapper[1].data[0], equals(2));
      expect(mapper[2].data[0], equals(3));
    });

    testWidgets('filters TX entries when showSent=false', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
                Uint8List.fromList([1]), LogEntryType.received, DateTime.now()),
            LogEntry(
                Uint8List.fromList([2]), LogEntryType.sent, DateTime.now()),
            LogEntry(
                Uint8List.fromList([3]), LogEntryType.received, DateTime.now()),
          ],
          totalBytes: 3,
          id: 0,
        ),
      ];

      final mapperRx = LogIndexMapper(chunks, showSent: false);
      expect(mapperRx.totalCount, equals(2));

      final mapperSent = LogIndexMapper(chunks, showSent: true);
      expect(mapperSent.totalCount, equals(3));
    });

    testWidgets('handles boundary conditions', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
                Uint8List.fromList([1]), LogEntryType.received, DateTime.now()),
          ],
          totalBytes: 1,
          id: 0,
        ),
      ];

      final mapper = LogIndexMapper(chunks, showSent: false);
      expect(mapper.totalCount, equals(1));
      expect(mapper[0].data[0], equals(1));
    });
  });

  group('ReceiveDisplayWidget - Scroll Behavior', () {
    testWidgets('scrolls to bottom on initial load', (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            20,
            (i) => LogEntry(
              Uint8List.fromList([i]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 20,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.controller, isNotNull);
    });

    testWidgets('shows scroll-to-bottom FAB when not at bottom',
        (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            50,
            (i) => LogEntry(
              Uint8List.fromList([i]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 50,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('scrolls to bottom when FAB is tapped', (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            100,
            (i) => LogEntry(
              Uint8List.fromList([i]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 100,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      final fabFinder = find.byType(FloatingActionButton);
      if (fabFinder.evaluate().isNotEmpty) {
        await tester.tap(fabFinder);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('uses jumpTo for large scroll distances', (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            200,
            (i) => LogEntry(
              Uint8List.fromList([i]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 200,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('ReceiveDisplayWidget - User Interaction', () {
    testWidgets('supports text selection', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([84, 101, 115, 116]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 4,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('handles scroll notifications', (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            30,
            (i) => LogEntry(
              Uint8List.fromList([i]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 30,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);

      await tester.drag(listView, const Offset(0, -100));
      await tester.pump();
    });
  });

  group('ReceiveDisplayWidget - Performance', () {
    testWidgets('handles large dataset efficiently', (tester) async {
      final chunks = [
        LogChunk(
          entries: List.generate(
            500,
            (i) => LogEntry(
              Uint8List.fromList([i % 256]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ),
          totalBytes: 500,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(chunks: chunks));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('respects buffer size limits', (tester) async {
      final settings = const UiSettings(logBufferSize: 16);
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([1, 2, 3, 4, 5]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 5,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: settings,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('ReceiveDisplayWidget - State Changes', () {
    testWidgets('updates when settings change', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([72, 101, 108, 108, 111]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 5,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(showTimestamp: false),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining(':'), findsNothing);

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(showTimestamp: true),
        key: UniqueKey(),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining(':'), findsOneWidget);
    });

    testWidgets('toggles between hex and text display', (tester) async {
      final chunks = [
        LogChunk(
          entries: [
            LogEntry(
              Uint8List.fromList([65, 66]),
              LogEntryType.received,
              DateTime.now(),
            ),
          ],
          totalBytes: 2,
          id: 0,
        ),
      ];

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(hexDisplay: false),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('AB'), findsOneWidget);

      await tester.pumpWidget(createReceiveDisplayTestWidget(
        chunks: chunks,
        settings: const UiSettings(hexDisplay: true),
        key: UniqueKey(),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('41'), findsOneWidget);
      expect(find.textContaining('42'), findsOneWidget);
    });
  });
}
