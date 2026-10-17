import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_settings_provider.dart';
import '../../providers/ui_controller.dart';
import '../../models/log_model.dart';
import '../../utils/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../services/log_export_service.dart';
import '../../src/rust/api.dart' as rust;

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
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;
  bool _stickToBottom = true;
  bool _programmaticScroll = false;
  bool _hasActiveSelection = false;
  bool _scrollScheduled = false;
  LogIndexMapper? _mapper;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      // Use a more lenient threshold to determine if at bottom, to avoid floating point precision issues
      final isBottom =
          _scrollController.position.extentAfter <=
          SkyPortConstants.scrollBottomThreshold;

      if (_isAtBottom != isBottom) {
        // Only setState when the state actually changes
        // Avoid unnecessary redraws during high-frequency data refreshes
        if (mounted) {
          setState(() {
            _isAtBottom = isBottom;
            // If the user scrolls to the bottom, auto-stick
            if (isBottom) {
              _stickToBottom = true;
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    if (force) {
      _stickToBottom = true;
      if (mounted) setState(() {});
    }

    if (!_stickToBottom || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_stickToBottom || !_scrollController.hasClients) return;
      _programmaticScroll = true;
      try {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } finally {
        _programmaticScroll = false;
      }
    });
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(uiSettingsProvider);
    final hasVisibleLogs = ref.watch(
      uiControllerProvider.select(
        (state) => state.logs.chunks.any(
          (chunk) => settings.showSent
              ? chunk.entries.isNotEmpty
              : chunk.rxEntries.isNotEmpty,
        ),
      ),
    );

    ref.listen(uiControllerProvider.select((state) => state.logs), (
      previous,
      next,
    ) {
      if (next.chunks.isNotEmpty && !_hasActiveSelection) {
        _scrollToBottom();
      }
    });

    return Expanded(
      child: Card.outlined(
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Consumer(
                    builder: (context, ref, child) {
                      final logState = ref.watch(
                        uiControllerProvider.select((state) => state.logs),
                      );
                      final cached = _mapper;
                      final mapper =
                          cached != null &&
                              identical(cached.chunks, logState.chunks) &&
                              cached.showSent == settings.showSent
                          ? cached
                          : (_mapper = LogIndexMapper(
                              logState.chunks,
                              showSent: settings.showSent,
                            ));
                      final int listLength = mapper.totalCount;

                      final monoStyle = theme.textTheme.bodyMedium!.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 18.0,
                        height: 1.2, // Compact line height
                      );
                      final dataTextStyle = monoStyle;

                      return Scrollbar(
                        controller: _scrollController,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (_programmaticScroll) return false;

                            // 只有当用户确实开始拖动时，才认为可能需要取消吸附
                            // 避免 SelectionArea 或其他微小抖动误触发 UserScrollNotification
                            if (notification is ScrollStartNotification) {
                              if (notification.dragDetails != null) {
                                // 用户开始拖拽
                                if (_stickToBottom) {
                                  setState(() => _stickToBottom = false);
                                }
                              }
                            }

                            // 桌面端鼠标滚轮通常会触发 UserScroll/ScrollUpdate，但没有 dragDetails。
                            // 退出粘滞的核心语义：用户向上滚动（离开底部）就取消 stick。
                            if (notification is UserScrollNotification) {
                              // Decreasing offset moves toward older rows.
                              if (notification.direction ==
                                  ScrollDirection.forward) {
                                if (_stickToBottom) {
                                  setState(() {
                                    _stickToBottom = false;
                                  });
                                }
                              }
                            }

                            // 兜底：部分平台只给 ScrollUpdateNotification（滚轮/触控板）。
                            if (notification is ScrollUpdateNotification) {
                              final delta = notification.scrollDelta;
                              if (delta != null && delta < 0) {
                                if (_stickToBottom) {
                                  setState(() {
                                    _stickToBottom = false;
                                  });
                                }
                              }
                            }
                            return false;
                          },
                          child: SelectionArea(
                            onSelectionChanged: (content) {
                              final hasSelection =
                                  content?.plainText.isNotEmpty ?? false;
                              if (_hasActiveSelection != hasSelection) {
                                _hasActiveSelection = hasSelection;
                              }
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              itemCount: listLength,
                              findChildIndexCallback: (key) {
                                return mapper.indexForId(
                                  (key as ValueKey<int>).value,
                                );
                              },
                              itemBuilder: (context, index) {
                                final entry = mapper[index];
                                final spans = entry.getSpans(
                                  hexDisplay: settings.hexDisplay,
                                  showTimestamp: settings.showTimestamp,
                                  showSent: settings.showSent,
                                  enableAnsi: settings.enableAnsi,
                                  baseStyle: dataTextStyle,
                                  timestampStyle: monoStyle.copyWith(
                                    color: theme.disabledColor,
                                  ),
                                  primaryColor: colorScheme.primary,
                                  onSurfaceColor: colorScheme.onSurface,
                                );

                                return SizedBox(
                                  key: ValueKey(entry.id),
                                  width: constraints.maxWidth,
                                  child: Text.rich(
                                    TextSpan(style: monoStyle, children: spans),
                                    textAlign: TextAlign.left,
                                    softWrap: true,
                                    overflow: TextOverflow.visible,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: hasVisibleLogs ? 76 : 8,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final state = ref.watch(
                          uiControllerProvider.select(
                            (state) => (
                              dataGap: state.dataGap,
                              logIncomplete: state.logIncomplete,
                              trimmedRecords: state.trimmedRecords,
                              trimmedBytes: state.trimmedBytes,
                            ),
                          ),
                        );
                        if (!state.dataGap &&
                            !state.logIncomplete &&
                            state.trimmedRecords == 0) {
                          return const SizedBox.shrink();
                        }
                        final l10n = AppLocalizations.of(context);
                        final messages = <String>[
                          if (state.dataGap) l10n.logDataGap,
                          if (state.logIncomplete) l10n.logIncomplete,
                          if (state.trimmedRecords > 0)
                            l10n.logTrimmed(
                              state.trimmedRecords,
                              state.trimmedBytes,
                            ),
                        ];
                        return Material(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(messages.join(' ')),
                          ),
                        );
                      },
                    ),
                  ),
                  if (hasVisibleLogs)
                    Positioned(
                      top: 4,
                      right: 0,
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: ButtonStyle(
                            minimumSize: const WidgetStatePropertyAll(
                              Size.square(32),
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.all(7),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => colorScheme.onSurface.withValues(
                                alpha:
                                    states.contains(WidgetState.hovered) ||
                                        states.contains(WidgetState.focused) ||
                                        states.contains(WidgetState.pressed)
                                    ? 1
                                    : 0.4,
                              ),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) =>
                                  states.contains(WidgetState.hovered) ||
                                      states.contains(WidgetState.focused) ||
                                      states.contains(WidgetState.pressed)
                                  ? colorScheme.onSurface.withValues(
                                      alpha: 0.08,
                                    )
                                  : Colors.transparent,
                            ),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: AppLocalizations.of(context).exportLogs,
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 18,
                              ),
                              onPressed: _exportLogs,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: AppLocalizations.of(
                                context,
                              ).clearReceiveArea,
                              icon: Builder(
                                builder: (context) => CustomPaint(
                                  size: const Size.square(18),
                                  painter: _BroomPainter(
                                    IconTheme.of(context).color!,
                                  ),
                                ),
                              ),
                              onPressed: () => ref
                                  .read(uiControllerProvider.notifier)
                                  .clearLog(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_stickToBottom)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        onPressed: () => _scrollToBottom(force: true),
                        child: const Icon(Icons.arrow_downward),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
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
