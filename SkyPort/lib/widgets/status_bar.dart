import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ui_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/ui_state.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          connection: state.connection,
          portName: state.portName,
          baudRate: state.baudRate,
          rxBytes: state.rxBytes,
          txBytes: state.txBytes,
          lastRxBytes: state.lastRxBytes,
        ),
      ),
    );
    final connection = state.connection;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    String statusText;
    Color statusColor;

    // 根据连接状态显示不同信息
    switch (connection) {
      case UiConnection.connected:
        statusText = l10n.connectedStatus(state.portName, state.baudRate);
        statusColor = Colors.green;
        break;
      case UiConnection.connecting:
        statusText = l10n.connecting;
        statusColor = colorScheme.tertiary;
        break;
      case UiConnection.reconfiguring:
        statusText = l10n.applyingConfiguration;
        statusColor = Colors.blue;
        break;
      case UiConnection.reconnecting:
        statusText = l10n.reconnecting;
        statusColor = colorScheme.tertiary;
        break;
      case UiConnection.disconnecting:
      case UiConnection.closing:
        statusText = l10n.disconnecting;
        statusColor = colorScheme.tertiary;
        break;
      case UiConnection.disconnected:
      case UiConnection.closed:
        statusText = l10n.disconnected;
        statusColor = Colors.grey;
        break;
    }

    final statsText = l10n.trafficStats(
      state.rxBytes,
      state.txBytes,
      state.lastRxBytes,
    );

    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            Row(
              children: [
                // 状态指示器（调和中显示脉动效果）
                if (connection == UiConnection.reconfiguring)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
                  )
                else
                  Icon(Icons.circle, color: statusColor, size: 10),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
            const Spacer(),
            Tooltip(
              message: l10n.trafficStatsTooltip,
              child: SelectableText(
                statsText,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
