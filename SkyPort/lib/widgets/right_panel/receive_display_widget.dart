import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import '../../providers/serial_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final isBottom = currentScroll >= (maxScroll - 20);

      if (_isAtBottom != isBottom) {
        setState(() {
          _isAtBottom = isBottom;
          if (isBottom) {
            _stickToBottom = true;
          }
        });
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
    }
    if (!_stickToBottom && !force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(uiSettingsProvider);

    ref.listen(dataLogProvider, (previous, next) {
      if ((previous?.length ?? 0) < next.length) {
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
                      final rawDataLog = ref.watch(dataLogProvider);
                      final dataLog = settings.showSent
                          ? rawDataLog
                          : rawDataLog
                              .where((e) => e.type == LogEntryType.received)
                              .toList();
                      final int listLength = dataLog.length;

                      final monoStyle = theme.textTheme.bodyMedium!.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 15.0,
                        height: 1.2, // Compact line height
                      );

                      final dataTextStyle = monoStyle.copyWith(
                        fontSize: 18.0,
                      );

                      return Scrollbar(
                        controller: _scrollController,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is UserScrollNotification) {
                              if (notification.direction ==
                                  ScrollDirection.reverse) {
                                if (_stickToBottom) {
                                  setState(() {
                                    _stickToBottom = false;
                                  });
                                }
                              }
                            } else if (notification
                                is ScrollUpdateNotification) {
                              if (notification.scrollDelta != null &&
                                  notification.scrollDelta! < 0 &&
                                  notification.metrics.pixels <
                                      notification.metrics.maxScrollExtent) {
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
                            child: ListView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              itemCount: listLength,
                              itemBuilder: (context, index) {
                                final entry = dataLog[index];

                                final isSent = entry.type == LogEntryType.sent;
                                final formattedTimestamp =
                                    DateFormat('HH:mm:ss.SSS')
                                        .format(entry.timestamp);

                                String dataText;
                                if (settings.hexDisplay) {
                                  dataText = entry.data
                                      .map((b) => b
                                          .toRadixString(16)
                                          .padLeft(2, '0')
                                          .toUpperCase())
                                      .join(' ');
                                } else {
                                  dataText = utf8.decode(entry.data,
                                      allowMalformed: true);
                                }

                                final lines = dataText.split('\n');

                                final List<TextSpan> spans = [];
                                for (int j = 0; j < lines.length; j++) {
                                  final lineText = lines[j];

                                  if (j == 0 && settings.showTimestamp) {
                                    spans.add(
                                      TextSpan(
                                        text: '$formattedTimestamp ',
                                        style: monoStyle.copyWith(
                                          color: theme.disabledColor,
                                        ),
                                      ),
                                    );
                                  }

                                  if (j == 0 && settings.showSent) {
                                    spans.add(
                                      TextSpan(
                                        text: isSent ? 'TX > ' : 'RX < ',
                                        style: monoStyle.copyWith(
                                          color: isSent
                                              ? colorScheme.primary
                                              : colorScheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }

                                  spans.add(
                                    TextSpan(
                                      text: lineText,
                                      style: dataTextStyle.copyWith(
                                        color: isSent
                                            ? colorScheme.primary
                                                .withValues(alpha: 0.8)
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                }

                                return SizedBox(
                                  width: constraints.maxWidth,
                                  child: Text.rich(
                                    TextSpan(
                                      style: monoStyle,
                                      children: spans,
                                    ),
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
