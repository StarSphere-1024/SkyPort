import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_settings_provider.dart';
import '../../providers/ui_controller.dart';
import '../../models/log_model.dart';
import '../../l10n/app_localizations.dart';
import '../../services/log_export_service.dart';
import '../../src/rust/api.dart' as rust;
import '../../providers/search_controller.dart';
import 'log_search_bar.dart';
import 'search_results_list.dart';

class LogIndexMapper {
  final List<LogChunk> chunks;
  final bool showSent;
  final List<int> _chunkStartIndices;
  late final int totalCount;

  LogIndexMapper(this.chunks, {required this.showSent})
    : _chunkStartIndices = [] {
    int current = 0;
    for (var c in chunks) {
      _chunkStartIndices.add(current);
      current += showSent ? c.entries.length : c.rxEntries.length;
    }
    totalCount = current;
  }

  LogEntry operator [](int index) {
    int chunkIndex = _binarySearchChunk(index);
    int offset = index - _chunkStartIndices[chunkIndex];
    if (showSent) {
      return chunks[chunkIndex].entries[offset];
    } else {
      return chunks[chunkIndex].rxEntries[offset];
    }
  }

  int? indexForId(int id) {
    final index = LogChunk.insertionIndex(chunks, id);
    if (index == chunks.length ||
        chunks[index].id != id ||
        (!showSent && chunks[index].rxEntries.isEmpty)) {
      return null;
    }
    return _chunkStartIndices[index];
  }

  int _binarySearchChunk(int targetIndex) {
    if (_chunkStartIndices.isEmpty) return 0;
    int min = 0;
    int max = _chunkStartIndices.length - 1;
    while (min <= max) {
      int mid = (min + max) >> 1;
      int startC = _chunkStartIndices[mid];
      int endC = mid == _chunkStartIndices.length - 1
          ? totalCount
          : _chunkStartIndices[mid + 1];

      if (targetIndex >= startC && targetIndex < endC) {
        return mid;
      }
      if (targetIndex < startC) {
        max = mid - 1;
      } else {
        min = mid + 1;
      }
    }
    return 0;
  }
}

class ReceiveDisplayWidget extends ConsumerStatefulWidget {
  const ReceiveDisplayWidget({super.key});

  @override
  ConsumerState<ReceiveDisplayWidget> createState() =>
      _ReceiveDisplayWidgetState();
}

class _ReceiveDisplayWidgetState extends ConsumerState<ReceiveDisplayWidget> {
  final FocusNode _searchFocus = FocusNode();

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final search = ref.read(searchControllerProvider.notifier);
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        ref.read(searchControllerProvider).visible) {
      search.close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        ref.read(searchControllerProvider).visible) {
      search.navigate(keyboard.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openSearch() {
    ref.read(searchControllerProvider.notifier).open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _exportLogs() async {
    final settings = ref.read(uiSettingsProvider);
    final state = ref.read(uiControllerProvider);
    await LogExportService.exportLogs(
      context: context,
      defaultPath: settings.logExportPath,
      portName: state.portName,
      export: (path) => ref
          .read(uiControllerProvider.notifier)
          .exportLog(
            path,
            rust.ExportOptions(
              showSent: settings.showSent,
              hex: settings.hexDisplay,
              timestamps: settings.showTimestamp,
              stripAnsi: settings.enableAnsi,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(uiSettingsProvider);
    final search = ref.watch(searchControllerProvider);
    final hasVisibleLogs = ref.watch(
      uiControllerProvider.select(
        (state) => state.logs.chunks.any(
          (chunk) => settings.showSent
              ? chunk.entries.isNotEmpty
              : chunk.rxEntries.isNotEmpty,
        ),
      ),
    );

    return Expanded(
      child: Card.outlined(
        color: colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReceiveToolbar(
              enabled: hasVisibleLogs,
              onExport: _exportLogs,
              onSearch: () {
                if (ref.read(searchControllerProvider).visible) {
                  ref.read(searchControllerProvider.notifier).close();
                } else {
                  _openSearch();
                }
              },
              onClear: () {
                ref.read(searchControllerProvider.notifier).clear();
                ref.read(uiControllerProvider.notifier).clearLog();
              },
            ),
            if (search.visible) LogSearchBar(focusNode: _searchFocus),
            Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(
                  uiControllerProvider.select(
                    (state) => (
                      dataGap: state.dataGap,
                      trimmedRecords: state.trimmedRecords,
                      trimmedBytes: state.trimmedBytes,
                    ),
                  ),
                );
                if (!state.dataGap && state.trimmedRecords == 0) {
                  return const SizedBox.shrink();
                }
                final l10n = AppLocalizations.of(context);
                final messages = <String>[
                  if (state.dataGap) l10n.logDataGap,
                  if (state.trimmedRecords > 0)
                    l10n.logTrimmed(state.trimmedRecords, state.trimmedBytes),
                ];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Material(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(messages.join(' ')),
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SearchResultsList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveToolbar extends StatelessWidget {
  const _ReceiveToolbar({
    required this.enabled,
    required this.onExport,
    required this.onClear,
    required this.onSearch,
  });

  final bool enabled;
  final VoidCallback onExport;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w500,
    );
    final actionStyle = theme.textTheme.labelLarge!;
    final textPainter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
    );
    double textWidth(String text, TextStyle? style) {
      textPainter.text = TextSpan(text: text, style: style);
      textPainter.layout();
      return textPainter.width;
    }

    const iconSize = 18.0;
    const buttonSize = 48.0;
    const actionSpacing = 4.0;
    const titleSpacing = 8.0;
    final headerWidth =
        iconSize + titleSpacing + textWidth(l10n.receiveData, titleStyle);
    final labeledActionsWidth =
        [l10n.searchLabel, l10n.exportLogs, l10n.clearLogs].fold<double>(
          actionSpacing * 2,
          (width, label) =>
              width +
              (textWidth(label, actionStyle) + iconSize + 6 + 16).clamp(
                buttonSize,
                double.infinity,
              ),
        );
    textPainter.dispose();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels =
              constraints.maxWidth >=
              headerWidth + titleSpacing + labeledActionsWidth;
          const compactActionsWidth = buttonSize * 3 + actionSpacing * 2;
          final showTitle =
              constraints.maxWidth >=
              headerWidth + titleSpacing + compactActionsWidth;
          Widget action(
            String label,
            Widget icon,
            VoidCallback onPressed, {
            String? tooltip,
            Key? key,
            bool alwaysEnabled = false,
          }) {
            return Tooltip(
              message: tooltip ?? label,
              child: TextButton(
                key: key,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  textStyle: actionStyle,
                  minimumSize: const Size(buttonSize, buttonSize),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: enabled || alwaysEnabled ? onPressed : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    if (showLabels) ...[const SizedBox(width: 6), Text(label)],
                  ],
                ),
              ),
            );
          }

          final header = Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              if (showTitle) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.receiveData,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ],
            ],
          );
          final actions = Wrap(
            spacing: actionSpacing,
            children: [
              action(
                l10n.searchLabel,
                const Icon(Icons.search, size: 18),
                onSearch,
                key: const ValueKey('search-open'),
                tooltip: l10n.searchOpen,
                alwaysEnabled: true,
              ),
              action(
                l10n.exportLogs,
                const Icon(Icons.file_download_outlined, size: 18),
                onExport,
              ),
              action(
                l10n.clearLogs,
                Builder(
                  builder: (context) => CustomPaint(
                    size: const Size.square(18),
                    painter: _BroomPainter(IconTheme.of(context).color!),
                  ),
                ),
                onClear,
                tooltip: l10n.clearReceiveArea,
              ),
            ],
          );
          if (constraints.maxWidth <
              iconSize + titleSpacing + compactActionsWidth) {
            return actions;
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: titleSpacing),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _BroomPainter extends CustomPainter {
  const _BroomPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(20, 3), const Offset(11, 12), paint);
    canvas.drawPath(
      Path()
        ..moveTo(9, 10)
        ..lineTo(14, 15)
        ..lineTo(10, 22)
        ..quadraticBezierTo(5, 21, 2, 16)
        ..close(),
      paint,
    );
    canvas.drawLine(const Offset(8, 15), const Offset(5, 19), paint);
    canvas.drawLine(const Offset(11, 17), const Offset(8, 21), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BroomPainter oldDelegate) => oldDelegate.color != color;
}
