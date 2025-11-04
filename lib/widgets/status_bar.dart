import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final config = ref.watch(serialConfigProvider);
    final errorMessage = ref.watch(errorProvider);

    final colorScheme = Theme.of(context).colorScheme;

    final l10n = AppLocalizations.of(context);
    String statusText;
    Color statusColor;

    switch (connection.status) {
      case ConnectionStatus.connected:
        statusText = l10n.connectedStatus(
            config?.portName ?? '-', config?.baudRate ?? 0);
        statusColor = colorScheme.primary;
        break;
      case ConnectionStatus.connecting:
        statusText = l10n.connecting;
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionStatus.disconnecting:
        statusText = l10n.disconnecting;
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionStatus.disconnected:
        statusText = l10n.disconnected;
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
              l10n.trafficStats(connection.rxBytes, connection.txBytes),
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
