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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        height: 30,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Rx: ${connection.rxBytes} | Tx: ${connection.txBytes}'),
            Row(
              children: [
                Icon(Icons.circle, color: statusColor, size: 12),
                const SizedBox(width: 8),
                Text(statusText),
              ],
            )
          ],
        ),
      ),
    );
  }
}
