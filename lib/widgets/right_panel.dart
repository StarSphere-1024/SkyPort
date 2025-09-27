import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import '../providers/serial_provider.dart';

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
    // Only scroll if the user is already at the bottom
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

    ref.listen(dataLogProvider, (previous, next) {
      // If a new item is added, scroll to bottom
      if ((previous?.length ?? 0) < next.length) {
        _scrollToBottom();
      }
    });

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: Card(
              child: Scrollbar(
                controller: _scrollController,
                child: Consumer(
                  builder: (context, ref, child) {
                    final dataLog = ref.watch(dataLogProvider);
                    final settings = ref.watch(settingsProvider);
                    final bool showLoadMore =
                        dataLog.length > _visibleItemCount;
                    final int listLength = (dataLog.length > _visibleItemCount)
                        ? _visibleItemCount
                        : dataLog.length;

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: listLength + (showLoadMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (showLoadMore && index == 0) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _visibleItemCount += 100;
                                  });
                                },
                                child: const Text('Load More'),
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
                        final formattedTimestamp =
                            DateFormat('HH:mm:ss.SSS').format(entry.timestamp);

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

                        return ListTile(
                            title: Align(
                              alignment: isSent
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(dataText),
                            ),
                            subtitle: Align(
                              alignment: isSent
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(
                                '${isSent ? "TX" : "RX"} - $formattedTimestamp',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            tileColor: isSent
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Consumer(builder: (context, ref, child) {
                        // Rebuild TextFormField when hexSend changes to re-run validator
                        final hexSend = ref.watch(settingsProvider).hexSend;
                        return TextFormField(
                          controller: _sendController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Enter data to send',
                          ),
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
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
                                return 'Invalid characters. Use 0-9, A-F.';
                              }
                              if (sanitizedValue.length % 2 != 0) {
                                return 'Hex string must have an even length.';
                              }
                            }
                            return null;
                          },
                          onChanged: (value) {
                            // Trigger validation on change
                            _formKey.currentState?.validate();
                          },
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
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
