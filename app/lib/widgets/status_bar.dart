import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ui_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/ui_state.dart';
import '../utils/connection_status.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          rxBytes: state.rxBytes,
          txBytes: state.txBytes,
          lastRxBytes: state.lastRxBytes,
          connection: state.connection,
          portName: state.portName,
          baudRate: state.baudRate,
        ),
      ),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final statsText = l10n.trafficStats(
      state.rxBytes,
      state.txBytes,
      state.lastRxBytes,
    );
    final disconnect =
        state.connection == UiConnection.connected ||
        state.connection == UiConnection.reconnecting;
    final canToggle =
        disconnect ||
        (state.connection == UiConnection.disconnected &&
            state.portName.isNotEmpty);
    final statusColor = connectionStatusColor(state.connection, theme);
    final status = connectionStatusLabel(state.connection, l10n);
    final portText = state.portName.isEmpty
        ? l10n.noPortSelected
        : '${state.portName} (${state.baudRate})';

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: AlignmentDirectional.centerEnd,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '$status · ${disconnect ? l10n.disconnect : l10n.connect}',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: !canToggle
                ? null
                : () {
                    final controller = ref.read(uiControllerProvider.notifier);
                    if (disconnect) {
                      controller.disconnect();
                    } else {
                      controller.connect();
                    }
                  },
            icon: Icon(Icons.circle, size: 10, color: statusColor),
          ),
          Expanded(
            child: Tooltip(
              message: '$status\n$portText',
              child: Text(
                portText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: '$statsText\n${l10n.trafficStatsTooltip}',
              child: Text(
                statsText,
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
