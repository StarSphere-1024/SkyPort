import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_settings_provider.dart';
import '../../providers/ui_controller.dart';
import '../../models/log_model.dart';
import '../../utils/constants.dart';
import '../../l10n/app_localizations.dart';

class LogIndexMapper {
  final List<LogChunk> chunks;
  final bool showSent;
  final List<int> _chunkStartIndices;
  final int totalCount;

  LogIndexMapper(this.chunks, {required this.showSent})
    : _chunkStartIndices = [],
      totalCount = chunks.fold(
        0,
        (sum, c) => sum + (showSent ? c.entries.length : c.rxEntries.length),
      ) {
    int current = 0;
    for (var c in chunks) {
      _chunkStartIndices.add(current);
      current += showSent ? c.entries.length : c.rxEntries.length;
    }
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      // Use a more lenient threshold to determine if at bottom, to avoid floating point precision issues
      final isBottom =
          currentScroll >= (maxScroll - SkyPortConstants.scrollBottomThreshold);

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

    if (!_stickToBottom) return;

    // If in stick mode, must perform scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      // Removed the early return check (pixels >= maxScroll - 5) as it was causing
      // issues with detecting new content arrival in some layout scenarios.

      _programmaticScroll = true;

      void onScrollComplete() {
        _programmaticScroll = false;
      }

      // If it's a forced operation, or the distance to the bottom is very far (possibly due to accumulated data), use jump for performance and immediacy
      // Otherwise, use animation for smoothness
      final distance = (maxScroll - _scrollController.position.pixels).abs();

      if (force || distance > SkyPortConstants.forceScrollDistance) {
        _scrollController.jumpTo(maxScroll);
        onScrollComplete();
      } else {
        _scrollController
            .animateTo(
              maxScroll,
              duration: Duration(
                milliseconds: SkyPortConstants.scrollAnimationDurationMs,
              ),
              curve: Curves.easeOut,
            )
            .then((_) {
              onScrollComplete();
            })
            .catchError((_) {
              // Animation might be interrupted
              onScrollComplete();
            });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(uiSettingsProvider);

    ref.listen(uiControllerProvider, (previous, next) {
      final prevBytes = previous?.logs.totalBytes ?? 0;
      if (next.logs.totalBytes > prevBytes && !_hasActiveSelection) {
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
                      final uiState = ref.watch(uiControllerProvider);
                      final logState = uiState.logs;
                      final mapper = LogIndexMapper(
                        logState.chunks,
                        showSent: settings.showSent,
                      );
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
                              // ScrollDirection.forward 表示 scroll position 在减小（向上滚）。
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
                    right: 8,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final state = ref.watch(uiControllerProvider);
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
