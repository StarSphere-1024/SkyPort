import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final config = ref.watch(serialConfigProvider);
    final errorMessage = ref.watch(errorProvider);

    final colorScheme = Theme.of(context).colorScheme;

    String statusText;
    Color statusColor;

    switch (connection.status) {
      case ConnectionStatus.connected:
        statusText = 'Connected to ${config?.portName}@${config?.baudRate}';
        statusColor = colorScheme.primary;
        break;
      case ConnectionStatus.connecting:
        statusText = 'Connecting...';
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionStatus.disconnecting:
        statusText = 'Disconnecting...';
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionStatus.disconnected:
        statusText = 'Disconnected';
        statusColor = colorScheme.error;
        break;
    }

    if (errorMessage != null) {
      statusText = errorMessage;
      statusColor = Theme.of(context).colorScheme.error;
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
        color: colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Rx: ${connection.rxBytes} | Tx: ${connection.txBytes}',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
            Row(
              children: [
                Icon(Icons.circle, color: statusColor, size: 10),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
