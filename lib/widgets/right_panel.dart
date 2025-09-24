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
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _sendController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
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
    final dataLog = ref.watch(dataLogProvider);
    final settings = ref.watch(settingsProvider);
    final connection = ref.watch(serialConnectionProvider);

    ref.listen(dataLogProvider, (_, __) {
      _scrollToBottom();
    });

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: Card(
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: dataLog.length,
                  itemBuilder: (context, index) {
                    final entry = dataLog[index];
                    final isSent = entry.type == LogEntryType.sent;
                    final formattedTimestamp =
                        DateFormat('HH:mm:ss.SSS').format(entry.timestamp);

                    String dataText;
                    if (settings.hexDisplay) {
                      dataText = entry.data
                          .map((b) =>
                              b.toRadixString(16).padLeft(2, '0').toUpperCase())
                          .join(' ');
                    } else {
                      dataText = utf8.decode(entry.data, allowMalformed: true);
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
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.3)
                          : Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withOpacity(0.3),
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sendController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Enter data to send',
                      ),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                    onPressed: connection.status == ConnectionStatus.connected
                        ? () {
                            ref
                                .read(serialConnectionProvider.notifier)
                                .send(_sendController.text);
                            _sendController.clear();
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
        ],
      ),
    );
  }
}
