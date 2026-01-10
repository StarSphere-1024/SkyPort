import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';
import '../l10n/app_localizations.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final config = ref.watch(serialConfigProvider);
    final error = ref.watch(errorProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    String statusText;
    Color statusColor;

    // Display error if exists, otherwise display status
    if (error != null) {
      statusColor = colorScheme.error;
      switch (error.type) {
        case AppErrorType.configNotSet:
          statusText = l10n.errConfigNotSet;
          break;
        case AppErrorType.portOpenTimeout:
          statusText = l10n.errPortOpenTimeout(error.rawMessage ?? '');
          break;
        case AppErrorType.portOpenFailed:
          statusText = l10n.errPortOpenFailed(error.rawMessage ?? '');
          break;
        case AppErrorType.portDisconnected:
          statusText = l10n.errPortDisconnected(error.rawMessage ?? '');
          break;
        case AppErrorType.writeFailed:
          statusText = l10n.errWriteFailed(error.rawMessage ?? '');
          break;
        case AppErrorType.invalidHexFormat:
          statusText = l10n.errInvalidHexFormat;
          break;
        case AppErrorType.cleanupError:
          statusText = l10n.errCleanupError(error.rawMessage ?? '');
          break;
        case AppErrorType.unknown:
        default:
          statusText = l10n.errUnknown(error.rawMessage ?? '');
          break;
      }
    } else {
      switch (connection.status) {
        case ConnectionStatus.connected:
          statusText = l10n.connectedStatus(
              config?.portName ?? '-', config?.baudRate ?? 0);
          statusColor = Colors.green;
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
          statusColor = Colors.grey;
          break;
      }
    }

    final statsText = l10n.trafficStats(
      connection.rxBytes,
      connection.txBytes,
      connection.lastRxBytes,
    );

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
          children: [
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
            ),
            const Spacer(),
            Tooltip(
              message: l10n.trafficStatsTooltip,
              child: SelectableText(
                statsText,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
