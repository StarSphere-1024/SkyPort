import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/providers/search_controller.dart';
import 'package:skyport/providers/ui_controller.dart';
import 'package:skyport/providers/ui_settings_provider.dart';
import 'package:skyport/src/rust/api.dart' as rust;

import '../../helpers/search_fixture.dart';

class _BatchController extends SearchFixtureController {
  void applyEvents(List<rust.Event> events) => state = state.withEvents(events);
}

void main() {
  test(
    'clear and identical pending replacement in one batch invalidates search',
    () async {
      const pending = 0xFFFFFFFFFFFFFFFF;
      final controller = _BatchController();
      final session = FixtureSearchSession(
        hits: [fixtureHit(pending, 0, 5)],
        views: {
          pending: fixtureView(
            pending,
            'ERROR',
            ranges: [const rust.SearchRange(start: 0, end: 5)],
            focus: const rust.SearchRange(start: 0, end: 5),
          ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          uiControllerProvider.overrideWith(() => controller),
          uiSettingsProvider.overrideWith(SearchFixtureSettings.new),
          searchBackendProvider.overrideWithValue(
            FixtureSearchBackend(controller, [session]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(uiControllerProvider);
      controller.upsert([fixtureRecord(pending, 'ERROR')]);
      final search = container.read(searchControllerProvider.notifier);
      search.setDraft('ERROR');
      await search.submit();
      expect(container.read(searchControllerProvider).total, 1);
      controller.applyEvents([
        const rust.Event(
          sequence: 1,
          kind: rust.EventType.logChanged,
          log: rust.LogDelta(
            upsert: [],
            removedIds: [pending],
            earliestId: 1,
            totalBytes: 0,
            trimmedBytes: 0,
            trimmedRecords: 0,
            incomplete: false,
          ),
        ),
        rust.Event(
          sequence: 2,
          kind: rust.EventType.dataReceived,
          log: rust.LogDelta(
            upsert: [fixtureRecord(pending, 'ERROR')],
            removedIds: [],
            earliestId: 1,
            totalBytes: 5,
            trimmedBytes: 0,
            trimmedRecords: 0,
            incomplete: false,
          ),
        ),
      ]);
      final result = container.read(searchControllerProvider);
      expect(result.invalidated, isTrue);
      expect(result.selectedHit, isNull);
      expect(result.total, 0);
      expect(session.cancellations, 1);
    },
  );
}
