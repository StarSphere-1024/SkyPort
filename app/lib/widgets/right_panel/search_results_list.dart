import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../../models/log_model.dart';
import '../../providers/search_controller.dart';
import '../../providers/ui_controller.dart';
import '../../providers/ui_settings_provider.dart';
import '../../src/rust/api.dart' as rust;
import 'receive_display_widget.dart';

/// Index-aware lazy layout is necessary: pixel estimates cannot locate a record
/// among arbitrary variable-height rows. Only the selected row has a GlobalKey.
class SearchResultsList extends ConsumerStatefulWidget {
  const SearchResultsList({super.key});

  @override
  ConsumerState<SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends ConsumerState<SearchResultsList> {
  final _items = ItemScrollController();
  final _offset = ScrollOffsetController();
  final _positions = ItemPositionsListener.create();
  bool _followLatest = false;
  bool _bottomScheduled = false;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_refineBottom);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_refineBottom);
    super.dispose();
  }

  void _refineBottom() {
    if (!_followLatest || ref.read(searchControllerProvider).hasResults) return;
    final last = (_mapper?.totalCount ?? 0) - 1;
    final position = _positions.itemPositions.value
        .where((item) => item.index == last)
        .firstOrNull;
    if (position == null || position.itemTrailingEdge > 1.001) {
      _scheduleBottom();
    }
  }

  void _scheduleBottom() {
    if (_bottomScheduled) return;
    _bottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomScheduled = false;
      if (!mounted || !_followLatest || !_items.isAttached) return;
      final last = (_mapper?.totalCount ?? 0) - 1;
      if (last < 0) return;
      final position = _positions.itemPositions.value
          .where((item) => item.index == last)
          .firstOrNull;
      if (position == null) {
        _items.jumpTo(index: last);
      } else {
        final delta =
            (position.itemTrailingEdge - 1) * (context.size?.height ?? 0);
        if (delta > 1) {
          _offset.animateScroll(
            offset: delta,
            duration: const Duration(milliseconds: 1),
          );
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  final _focusText = GlobalKey();
  int _scheduledNavigation = -1;
  LogIndexMapper? _mapper;

  void _reveal(int navigation, int recordId) {
    if (_scheduledNavigation == navigation) return;
    _scheduledNavigation = navigation;
    _followLatest = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_items.isAttached ||
          _scheduledNavigation != navigation) {
        return;
      }
      final index = _mapper?.indexForId(recordId);
      if (index == null) return;
      _items.jumpTo(index: index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _scheduledNavigation != navigation) return;
        if (!ref.read(searchControllerProvider).visible) return;
        final render = _focusText.currentContext?.findRenderObject();
        final view = ref.read(searchControllerProvider).selectedView;
        final focus = view?.focusRange;
        if (render is! RenderParagraph || focus == null) return;
        // Prefix labels and clipping indicators precede the canonical UTF-16 view.
        final text = render.text.toPlainText();
        final prefixLength = text.length - view!.text.length;
        final boxes = render.getBoxesForSelection(
          TextSelection(
            baseOffset: prefixLength + focus.start,
            extentOffset: prefixLength + focus.end,
          ),
        );
        if (boxes.isEmpty) return;
        final viewport = context.size?.height ?? 0;
        final delta = boxes.first.top - viewport * .25;
        if (delta > 0) {
          _offset.animateScroll(
            offset: delta,
            duration: const Duration(milliseconds: 1),
          );
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final settings = ref.watch(uiSettingsProvider);
    final logs = ref.watch(uiControllerProvider.select((state) => state.logs));
    final options = search.hasResults
        ? search.options!
        : ref.read(searchControllerProvider.notifier).currentOptions;
    ref.listen(uiControllerProvider.select((state) => state.logs), (_, next) {
      if (_followLatest && !ref.read(searchControllerProvider).hasResults) {
        _scheduleBottom();
      }
    });
    final cached = _mapper;
    final mapper =
        cached != null &&
            identical(cached.chunks, logs.chunks) &&
            cached.showSent == options.showSent
        ? cached
        : (_mapper = LogIndexMapper(logs.chunks, showSent: options.showSent));
    final hit = search.selectedHit;
    if (hit != null) _reveal(search.navigation, hit.recordId);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!.copyWith(
      fontFamily: 'monospace',
      fontSize: 18,
      height: 1.3,
    );
    if (mapper.totalCount == 0) return const SizedBox.shrink();
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle &&
                _followLatest) {
              setState(() => _followLatest = false);
            }
            return false;
          },
          child: SelectionArea(
            child: ScrollablePositionedList.builder(
              key: const ValueKey('search-results'),
              itemScrollController: _items,
              scrollOffsetController: _offset,
              itemPositionsListener: _positions,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: mapper.totalCount,
              itemBuilder: (context, index) {
                final entry = mapper[index];
                final selected = hit?.recordId == entry.id;
                return _SearchResultRow(
                  key: ValueKey((search.generation, entry)),
                  entry: entry,
                  generation: search.generation,
                  showHighlights: search.visible && search.hasResults,
                  focusIndex: selected ? search.selectedIndex : null,
                  selectedView: selected && search.visible
                      ? search.selectedView
                      : null,
                  focusTextKey: selected ? _focusText : null,
                  style: style,
                  showTimestamp: settings.showTimestamp,
                  showSent: options.showSent,
                  hex: options.hex,
                  ansi: options.stripAnsi,
                );
              },
            ),
          ),
        ),
        if (!search.hasResults && !_followLatest)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              onPressed: () {
                setState(() => _followLatest = true);
                _scheduleBottom();
              },
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }
}

class _SearchResultRow extends ConsumerStatefulWidget {
  final LogEntry entry;
  final int generation;
  final int? focusIndex;
  final rust.SearchRecordView? selectedView;
  final Key? focusTextKey;
  final TextStyle style;
  final bool showTimestamp;
  final bool showSent;
  final bool hex;
  final bool ansi;
  final bool showHighlights;
  const _SearchResultRow({
    super.key,
    required this.entry,
    required this.generation,
    required this.focusIndex,
    required this.selectedView,
    required this.focusTextKey,
    required this.style,
    required this.showTimestamp,
    required this.showSent,
    required this.hex,
    required this.ansi,
    required this.showHighlights,
  });

  @override
  ConsumerState<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends ConsumerState<_SearchResultRow> {
  late Future<rust.SearchRecordView?> _view;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SearchResultRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusIndex != widget.focusIndex ||
        oldWidget.generation != widget.generation ||
        oldWidget.showHighlights != widget.showHighlights) {
      _load();
    }
  }

  void _load() {
    if (!widget.showHighlights) {
      _view = Future.value();
      return;
    }
    _view = widget.selectedView != null
        ? Future.value(widget.selectedView)
        : ref
              .read(searchControllerProvider.notifier)
              .recordView(widget.entry.id, focusIndex: widget.focusIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timestampStyle = widget.style.copyWith(
      color: Theme.of(context).disabledColor,
    );
    return FutureBuilder<rust.SearchRecordView?>(
      future: _view,
      initialData: widget.selectedView,
      builder: (context, snapshot) {
        final view =
            widget.selectedView ??
            (snapshot.connectionState == ConnectionState.done
                ? snapshot.data
                : null);
        final entry = widget.entry;
        // A late view is never rendered against a different current record.
        final valid =
            widget.showHighlights &&
            view != null &&
            view.recordId == entry.id &&
            view.timestampMs == entry.timestamp.millisecondsSinceEpoch &&
            view.sourceLength == entry.data.length;
        final focus = valid ? view.focusRange : null;
        final useCanonical =
            valid &&
            (view.ranges.isNotEmpty ||
                view.leadingClipped ||
                view.trailingClipped);
        final spans = useCanonical
            ? entry.getSearchSpans(
                text: view.text,
                ranges: [
                  for (final range in view.ranges)
                    (start: range.start, end: range.end),
                ],
                focus: focus == null
                    ? null
                    : (start: focus.start, end: focus.end),
                showTimestamp: widget.showTimestamp,
                showSent: widget.showSent,
                baseStyle: widget.style,
                timestampStyle: timestampStyle,
                primaryColor: colors.primary,
                onSurfaceColor: colors.onSurface,
                matchColor: colors.secondaryContainer,
                selectedColor: colors.tertiaryContainer,
              )
            : entry.getSpans(
                hexDisplay: widget.hex,
                showTimestamp: widget.showTimestamp,
                showSent: widget.showSent,
                enableAnsi: widget.ansi,
                baseStyle: widget.style,
                timestampStyle: timestampStyle,
                primaryColor: colors.primary,
                onSurfaceColor: colors.onSurface,
              );
        final l10n = AppLocalizations.of(context);
        return Column(
          key: ValueKey('search-row-${entry.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (valid && view.leadingClipped)
              Text(
                l10n.searchContextBefore,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text.rich(
              key: widget.focusTextKey,
              TextSpan(style: widget.style, children: spans),
              textAlign: TextAlign.left,
              softWrap: true,
            ),
            if (valid && view.trailingClipped)
              Text(
                l10n.searchContextAfter,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}
