import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../../models/log_model.dart';
import '../../models/search_model.dart';
import '../../providers/search_controller.dart';
import '../../providers/ui_controller.dart';
import '../../providers/ui_settings_provider.dart';
import '../../src/rust/api.dart' as rust;
import '../../utils/constants.dart';
import 'receive_display_widget.dart';

/// Index-aware lazy layout locates search hits among variable-height rows.
/// Only the selected text needs a GlobalKey.
class SearchResultsList extends ConsumerStatefulWidget {
  const SearchResultsList({super.key});

  @override
  ConsumerState<SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends ConsumerState<SearchResultsList> {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  bool _followLatest = true;
  bool _bottomScheduled = false;
  bool _manualScrolling = false;
  BuildContext? _tailContext;
  LogEntry? _tailEntry;
  bool _hasActiveSelection = false;
  final _rowContexts = <int, _SearchResultRowState>{};
  late final SearchController _searchController;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_refineBottom);
    _searchController = ref.read(searchControllerProvider.notifier);
    _searchController.setPositionReader(_readPosition);
  }

  @override
  void dispose() {
    _searchController.setPositionReader(null);
    _positions.itemPositions.removeListener(_refineBottom);
    super.dispose();
  }

  SearchReadingPosition? _readPosition() {
    final mapper = _mapper;
    if (mapper == null) return null;
    final visible =
        _positions.itemPositions.value
            .where((position) => position.itemTrailingEdge > 0)
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    for (final position in visible) {
      if (position.index >= mapper.totalCount) continue;
      final entry = mapper[position.index];
      final row = _rowContexts[entry.id];
      if (row == null || !row.context.mounted) continue;
      final offset = row.readingOffset();
      if (offset != null) {
        return (recordId: entry.id, offset: offset);
      }
    }
    return null;
  }

  void _manualScroll() {
    _manualScrolling = true;
    final search = ref.read(searchControllerProvider);
    ref.read(searchControllerProvider.notifier).userScrolled();
    _suppressedNavigation = search.navigation;
    _scheduledNavigation = search.navigation;
    _revealRevision++;
    if (_followLatest) setState(() => _followLatest = false);
  }

  void _refineBottom() {
    if (_followLatest &&
        !_hasActiveSelection &&
        !ref.read(searchControllerProvider).visible) {
      _scheduleBottom();
    }
  }

  void _scheduleBottom() {
    if (_bottomScheduled) return;
    _bottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomScheduled = false;
      if (!mounted ||
          !_followLatest ||
          _hasActiveSelection ||
          ref.read(searchControllerProvider).visible ||
          !_items.isAttached) {
        return;
      }
      final last = (_mapper?.totalCount ?? 0) - 1;
      if (last < 0) return;
      final tail = _tailContext;
      if (tail == null ||
          !tail.mounted ||
          !identical(_tailEntry, _mapper![last])) {
        // Never align a newly appended row's top with the viewport's top.
        _items.jumpTo(index: last, alignment: 1);
      } else {
        final render = tail.findRenderObject() as RenderBox;
        final viewport = RenderAbstractViewport.of(render) as RenderBox;
        final position = Scrollable.of(tail).position;
        final bottom = render
            .localToGlobal(Offset(0, render.size.height), ancestor: viewport)
            .dy;
        final target = (position.pixels + bottom + 8 - viewport.size.height)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if ((target - position.pixels).abs() > 0.5) position.jumpTo(target);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  final _focusText = GlobalKey();
  int _scheduledNavigation = -1;
  int _suppressedNavigation = -1;
  int _revealRevision = 0;
  LogIndexMapper? _mapper;

  void _reveal(int navigation, int recordId) {
    if (_scheduledNavigation == navigation ||
        _suppressedNavigation == navigation) {
      return;
    }
    _scheduledNavigation = navigation;
    _followLatest = false;
    final revision = _revealRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_items.isAttached ||
          _scheduledNavigation != navigation ||
          _revealRevision != revision) {
        return;
      }
      if (!ref.read(searchControllerProvider).visible || _revealFocus()) return;
      final index = _mapper?.indexForId(recordId);
      if (index == null) return;
      final below = _positions.itemPositions.value.any(
        (position) =>
            position.itemLeadingEdge < 1 &&
            position.itemTrailingEdge > 0 &&
            position.index < index,
      );
      _items.jumpTo(index: index, alignment: below ? 1 : 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _scheduledNavigation != navigation ||
            _revealRevision != revision) {
          return;
        }
        if (ref.read(searchControllerProvider).visible) _revealFocus();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  bool _revealFocus() {
    final textContext = _focusText.currentContext;
    var render = textContext?.findRenderObject();
    while (render is RenderProxyBox) {
      render = render.child;
    }
    final view = ref.read(searchControllerProvider).selectedView;
    final focus = view?.focusRange;
    if (render is! RenderParagraph || focus == null) return false;
    // Prefix labels precede the canonical UTF-16 view.
    final prefixLength = render.text.toPlainText().length - view!.text.length;
    final boxes = render.getBoxesForSelection(
      TextSelection(
        baseOffset: prefixLength + focus.start,
        extentOffset: prefixLength + focus.end,
      ),
    );
    if (boxes.isEmpty) return false;
    final viewport = RenderAbstractViewport.of(render) as RenderBox;
    var bounds = boxes.first.toRect();
    for (var index = 1; index < boxes.length; index++) {
      bounds = bounds.expandToInclude(boxes[index].toRect());
    }
    if (bounds.height > viewport.size.height) bounds = boxes.first.toRect();
    final rect = MatrixUtils.transformRect(
      render.getTransformTo(viewport),
      bounds,
    );
    final delta = rect.top < 0
        ? rect.top
        : rect.bottom > viewport.size.height
        ? rect.bottom - viewport.size.height
        : 0.0;
    final position = Scrollable.of(textContext!).position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() > 0.5) position.jumpTo(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final settings = ref.watch(uiSettingsProvider);
    final logs = ref.watch(uiControllerProvider.select((state) => state.logs));
    final options = search.hasResults
        ? search.options!
        : ref.read(searchControllerProvider.notifier).currentOptions;
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
    if (mapper.totalCount == 0) {
      _tailContext = null;
      _tailEntry = null;
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final dragging =
                notification is ScrollStartNotification &&
                notification.dragDetails != null;
            final scrolling =
                notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle;
            if (dragging || scrolling) _manualScroll();
            if (notification is ScrollEndNotification && _manualScrolling) {
              _manualScrolling = false;
              if (!ref.read(searchControllerProvider).visible &&
                  !_hasActiveSelection &&
                  notification.metrics.extentAfter <=
                      SkyPortConstants.scrollBottomThreshold) {
                setState(() => _followLatest = true);
                _scheduleBottom();
              }
            }
            return false;
          },
          child: SelectionArea(
            onSelectionChanged: (selection) {
              _hasActiveSelection = selection?.plainText.isNotEmpty ?? false;
            },
            child: ScrollablePositionedList.builder(
              key: const ValueKey('search-results'),
              itemScrollController: _items,
              itemPositionsListener: _positions,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: mapper.totalCount,
              itemBuilder: (context, index) {
                final entry = mapper[index];
                final selected = hit?.recordId == entry.id;
                return _SearchResultRow(
                  key: ValueKey((search.generation, entry)),
                  entry: entry,
                  onTailBuilt: index == mapper.totalCount - 1
                      ? (context) {
                          _tailContext = context;
                          _tailEntry = entry;
                        }
                      : null,
                  onRowBuilt: (row) => _rowContexts[entry.id] = row,
                  onRowDisposed: (row) {
                    if (identical(_rowContexts[entry.id], row)) {
                      _rowContexts.remove(entry.id);
                    }
                  },
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
        if (!search.visible && !search.hasResults && !_followLatest)
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
  final ValueChanged<BuildContext>? onTailBuilt;
  final ValueChanged<_SearchResultRowState> onRowBuilt;
  final ValueChanged<_SearchResultRowState> onRowDisposed;
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
    this.onTailBuilt,
    required this.generation,
    required this.onRowBuilt,
    required this.onRowDisposed,
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
  rust.SearchRecordView? _renderedView;
  String? _renderedText;

  int? readingOffset() {
    final root = context.findRenderObject();
    final text = _renderedText;
    if (root == null || text == null) return null;
    RenderParagraph? paragraph;
    RenderParagraph? longestParagraph;
    void visit(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph) {
        longestParagraph ??= object;
        if (object.text
            .toPlainText()
            .replaceAll('\uFFFC', '\n')
            .contains(text)) {
          paragraph = object;
          return;
        }
        if (longestParagraph!.text.toPlainText().length <
            object.text.toPlainText().length) {
          longestParagraph = object;
        }
      }
      object.visitChildren(visit);
    }

    visit(root);
    final textRender = paragraph ?? longestParagraph;
    if (textRender == null || !textRender.hasSize) return null;
    final viewport = RenderAbstractViewport.of(textRender) as RenderBox?;
    if (viewport == null) return null;
    final top = textRender.globalToLocal(viewport.localToGlobal(Offset.zero));
    final rawOffset = textRender.getPositionForOffset(Offset(0, top.dy)).offset;
    final plainText = textRender.text.toPlainText();
    final suffix =
        _renderedView == null &&
            widget.entry.getDisplayTextPreview(widget.hex).truncated
        ? ' ... [TRUNCATED]'.length
        : 0;
    final prefix = _renderedView == null
        ? (widget.showTimestamp ? 13 : 0) + (widget.showSent ? 5 : 0)
        : plainText.length - _renderedView!.text.length;
    final textLength = (plainText.length - prefix - suffix)
        .clamp(0, plainText.length)
        .toInt();
    final localOffset = (rawOffset - prefix).clamp(0, textLength).toInt();
    return (_renderedView?.startOffset ?? 0) + localOffset;
  }

  @override
  void dispose() {
    widget.onRowDisposed(this);
    super.dispose();
  }

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
    widget.onTailBuilt?.call(context);
    widget.onRowBuilt(this);
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
        _renderedView = useCanonical ? view : null;
        _renderedText = useCanonical
            ? view.text
            : entry.getDisplayTextPreview(widget.hex).text;
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
