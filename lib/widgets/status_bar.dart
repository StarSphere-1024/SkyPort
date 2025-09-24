import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final config = ref.watch(serialConfigProvider);

    String statusText = 'Disconnected';
    Color statusColor = Colors.red;

    if (connection.status == ConnectionStatus.connected) {
      statusText = 'Connected to ${config?.portName}@${config?.baudRate}';
      statusColor = Colors.green;
    } else if (connection.errorMessage != null) {
      statusText = connection.errorMessage!;
      statusColor = Theme.of(context).colorScheme.error;
    }

    return BottomAppBar(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Rx: ${connection.rxBytes} | Tx: ${connection.txBytes}',
              style: const TextStyle(fontSize: 12),
            ),
            Row(
              children: [
                Icon(Icons.circle, color: statusColor, size: 10),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
