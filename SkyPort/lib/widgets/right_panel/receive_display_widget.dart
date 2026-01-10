import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

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

  TextStyle _ansiStateToStyle(dynamic state, TextStyle baseStyle) {
    Color? fg;
    Color? bg;
    bool bold = false;
    bool italic = false;
    bool underline = false;

    // Helper to convert ANSI color logic to Flutter Color
    Color? getFlutterColor(dynamic ansiColorObject) {
      if (ansiColorObject == null) return null;
      try {
        final runtimeTypeStr = ansiColorObject.runtimeType.toString();
        // Support standard 16 colors
        if (runtimeTypeStr.contains('Color16')) {
          final dynamic colorEnum = ansiColorObject.color;
          final int index = colorEnum.index as int;
          switch (index) {
            case 0:
              return Colors.black;
            case 1:
              return Colors.red;
            case 2:
              return Colors.green;
            case 3:
              return Colors.yellow;
            case 4:
              return Colors.blue;
            case 5:
              return Colors.purple; // Magenta
            case 6:
              return Colors.cyan;
            case 7:
              return Colors.white70; // Standard white (dimmer)

            // Bright/Bold colors
            case 8:
              return Colors.grey; // Bright Black
            case 9:
              return Colors.redAccent;
            case 10:
              return Colors.greenAccent;
            case 11:
              return Colors.yellowAccent;
            case 12:
              return Colors.blueAccent;
            case 13:
              return Colors.purpleAccent;
            case 14:
              return Colors.cyanAccent;
            case 15:
              return Colors.white; // Bright White

            default:
              return null;
          }
        }
        // Extension point: Support Color256 or RGB if needed in future
      } catch (e) {
        // debugPrint('ANSI Color Parse Error: $e');
      }
      return null;
    }

    try {
      if (state != null) {
        fg = getFlutterColor(state.foreground);
        bg = getFlutterColor(state.background);

        try {
          if (state.isBold == true) bold = true;
        } catch (_) {}
        try {
          if (state.isItalicized == true) italic = true;
        } catch (_) {}
        try {
          if (state.isSinglyUnderlined == true) underline = true;
        } catch (_) {}
      }
    } catch (e) {
      // debugPrint('ANSI State Parse Error: $e');
    }

    return baseStyle.copyWith(
      color: fg,
      backgroundColor: bg,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline ? TextDecoration.underline : null,
    );
  }

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

                                String dataText =
                                    entry.getDisplayText(settings.hexDisplay);

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

                                  if (settings.enableAnsi) {
                                    final parser = ansi.AnsiParser(lineText);
                                    for (final match in parser.matches) {
                                      final text = lineText.substring(
                                          match.start, match.end);

                                      if (text.startsWith('\x1b')) {
                                        continue;
                                      }

                                      spans.add(TextSpan(
                                        text: text,
                                        style: _ansiStateToStyle(
                                            match.state,
                                            dataTextStyle.copyWith(
                                              color: isSent
                                                  ? colorScheme.primary
                                                      .withValues(alpha: 0.8)
                                                  : colorScheme.onSurface,
                                            )),
                                      ));
                                    }
                                  } else {
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
