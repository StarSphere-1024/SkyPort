import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';

import '../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class RightPanel extends ConsumerStatefulWidget {
  const RightPanel({super.key});

  @override
  ConsumerState<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends ConsumerState<RightPanel> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _visibleItemCount = 100;
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.atEdge) {
        if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
          setState(() {
            _isAtBottom = true;
          });
        }
      } else {
        setState(() {
          _isAtBottom = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sendController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_isAtBottom) return;
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
    final connection = ref.watch(serialConnectionProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(uiSettingsProvider);

    ref.listen(dataLogProvider, (previous, next) {
      if ((previous?.length ?? 0) < next.length) {
        _scrollToBottom();
      }
    });

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: Card.outlined(
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Scrollbar(
                      controller: _scrollController,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Consumer(
                              builder: (context, ref, child) {
                                final rawDataLog = ref.watch(dataLogProvider);
                                final dataLog = settings.showSent
                                    ? rawDataLog
                                    : rawDataLog
                                        .where((e) =>
                                            e.type == LogEntryType.received)
                                        .toList();
                                final bool showLoadMore =
                                    dataLog.length > _visibleItemCount;
                                final int listLength =
                                    (dataLog.length > _visibleItemCount)
                                        ? _visibleItemCount
                                        : dataLog.length;

                                final l10n = AppLocalizations.of(context);
                                final monoStyle =
                                    theme.textTheme.bodyMedium!.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 15.0,
                                  height: 1.2, // Compact line height
                                );

                                final dataTextStyle = monoStyle.copyWith(
                                  fontSize: 18.0,
                                );

                                List<TextSpan> allSpans = [];

                                if (showLoadMore) {
                                  allSpans.add(
                                    TextSpan(
                                      text: '${l10n.loadMore}\n',
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          setState(() {
                                            _visibleItemCount += 100;
                                          });
                                        },
                                      style: theme.textTheme.labelMedium,
                                    ),
                                  );
                                }

                                final startIndex = dataLog.length - listLength;
                                for (int i = startIndex;
                                    i < dataLog.length;
                                    i++) {
                                  final entry = dataLog[i];
                                  final isSent =
                                      entry.type == LogEntryType.sent;
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

                                  // Split dataText into lines for unified formatting
                                  final lines = dataText.split('\n');

                                  for (int j = 0; j < lines.length; j++) {
                                    final lineText = lines[j];

                                    allSpans.addAll([
                                      if (j == 0 && settings.showTimestamp)
                                        TextSpan(
                                          text: '$formattedTimestamp ',
                                          style: monoStyle.copyWith(
                                            color: theme.disabledColor,
                                          ),
                                        ),
                                      if (j == 0 && settings.showSent)
                                        TextSpan(
                                          text: isSent ? "TX > " : "RX < ",
                                          style: monoStyle.copyWith(
                                            color: isSent
                                                ? colorScheme.primary
                                                : colorScheme.onSurface,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      TextSpan(
                                        text: '$lineText\n',
                                        style: dataTextStyle.copyWith(
                                          color: isSent
                                              ? colorScheme.primary
                                                  .withValues(alpha: 0.8)
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                    ]);
                                  }
                                }

                                return SelectableText.rich(
                                  TextSpan(children: allSpans),
                                  textAlign: TextAlign.left,
                                  style: monoStyle,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card.filled(
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Consumer(builder: (context, ref, child) {
                        final hexSend = ref.watch(uiSettingsProvider).hexSend;
                        final l10n = AppLocalizations.of(context);
                        return TextFormField(
                          controller: _sendController,
                          style: const TextStyle(fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: l10n.enterDataToSend,
                            isDense: true,
                          ),
                          keyboardType: TextInputType.multiline,
                          minLines: 1,
                          maxLines: 5,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            if (hexSend) {
                              if (value == null || value.isEmpty) {
                                return null;
                              }
                              final sanitizedValue =
                                  value.replaceAll(RegExp(r'\s+'), '');
                              if (sanitizedValue.isEmpty) {
                                return null;
                              }
                              if (!RegExp(r'^[0-9a-fA-F]+$')
                                  .hasMatch(sanitizedValue)) {
                                return l10n.invalidHexChars;
                              }
                              if (sanitizedValue.length % 2 != 0) {
                                return l10n.hexEvenLength;
                              }
                            }
                            return null;
                          },
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(AppLocalizations.of(context).send),
                      onPressed: connection.status == ConnectionStatus.connected
                          ? () {
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(serialConnectionProvider.notifier)
                                    .send(_sendController.text);
                              }
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16.0, horizontal: 24.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
