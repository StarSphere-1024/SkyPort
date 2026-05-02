import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/serial/serial_port_manager.dart';
import '../l10n/app_localizations.dart';
import '../models/connection_status.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serialPortManagerProvider);
    final connection = state.connection;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    String statusText;
    Color statusColor;

    // 根据连接状态显示不同信息
    switch (connection.state) {
      case ConnectionState.connected:
        // 显示实际连接使用的配置
        statusText = l10n.connectedStatus(
            connection.appliedConfig?.portName ?? '-',
            connection.appliedConfig?.baudRate ?? 0);
        statusColor = Colors.green;
        break;
      case ConnectionState.connecting:
        statusText = l10n.connecting;
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionState.reconfiguring:
        // 新增：显示配置变更中
        statusText = '应用配置中...';
        statusColor = Colors.blue;
        break;
      case ConnectionState.reconnecting:
        statusText = l10n.reconnecting;
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionState.disconnecting:
        statusText = l10n.disconnecting;
        statusColor = colorScheme.tertiary;
        break;
      case ConnectionState.disconnected:
        statusText = l10n.disconnected;
        statusColor = Colors.grey;
        break;
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
                // 状态指示器（调和中显示脉动效果）
                if (state.isReconciling)
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
