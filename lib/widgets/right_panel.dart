import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

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
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Scrollbar(
                  controller: _scrollController,
                  child: Consumer(
                    builder: (context, ref, child) {
                      final dataLog = ref.watch(dataLogProvider);
                      final settings = ref.watch(uiSettingsProvider);
                      final bool showLoadMore =
                          dataLog.length > _visibleItemCount;
                      final int listLength =
                          (dataLog.length > _visibleItemCount)
                              ? _visibleItemCount
                              : dataLog.length;

                      final l10n = AppLocalizations.of(context);

                      // 定义终端风格的字体样式
                      final monoStyle = theme.textTheme.bodyMedium!.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 14.0,
                        height: 1.2, // 紧凑行高
                      );

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        itemCount: listLength + (showLoadMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (showLoadMore && index == 0) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _visibleItemCount += 100;
                                    });
                                  },
                                  child: Text(l10n.loadMore),
                                ),
                              ),
                            );
                          }

                          final entryIndex = showLoadMore
                              ? (dataLog.length - listLength) + (index - 1)
                              : index;
                          if (entryIndex < 0) return const SizedBox.shrink();

                          final entry = dataLog[entryIndex];
                          final isSent = entry.type == LogEntryType.sent;
                          final formattedTimestamp = DateFormat('HH:mm:ss.SSS')
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
                            dataText =
                                utf8.decode(entry.data, allowMalformed: true);
                          }

                          // 终端式布局：每行极简显示
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 1.0, horizontal: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. 时间戳 (可选)
                                if (settings.showTimestamp)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Text(
                                      formattedTimestamp,
                                      style: monoStyle.copyWith(
                                        color: theme.disabledColor,
                                      ),
                                    ),
                                  ),

                                // 2. 方向指示符 (TX/RX)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Text(
                                    isSent ? "TX >" : "RX <",
                                    style: monoStyle.copyWith(
                                      color: isSent
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                // 3. 数据内容
                                Expanded(
                                  child: Text(
                                    dataText,
                                    style: monoStyle.copyWith(
                                      // 接收内容用默认色，发送内容用稍微淡一点的颜色区分，或者保持一致
                                      color: isSent
                                          ? colorScheme.primary
                                              .withValues(alpha: 0.8)
                                          : colorScheme.onSurface,
                                      fontSize: 18.0, // 数据内容字体更大
                                    ),
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card.filled(
            color: colorScheme.surface,
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
                            isDense: true, // 稍微紧凑一点的输入框
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
                          onChanged: (value) {
                            _formKey.currentState?.validate();
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
