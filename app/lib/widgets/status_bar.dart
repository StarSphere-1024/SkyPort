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
          rxBytesPerSecond: state.rxBytesPerSecond,
          connection: state.connection,
          portName: state.portName,
          baudRate: state.baudRate,
          dataBits: state.dataBits,
          parity: state.parity,
          stopBits: state.stopBits,
        ),
      ),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final statsText =
        'RX ${_formatIecBytes(state.rxBytes)} · '
        'TX ${_formatIecBytes(state.txBytes)} · '
        '${_formatIecBytes(state.rxBytesPerSecond)}/s';
    final disconnect =
        state.connection == UiConnection.connected ||
        state.connection == UiConnection.reconnecting;
    final canToggle =
        disconnect ||
        (state.connection == UiConnection.disconnected &&
            state.portName.isNotEmpty);
    final statusColor = connectionStatusColor(state.connection, theme);
    final status = connectionStatusLabel(state.connection, l10n);
    final portText = state.portName.isEmpty ? '' : state.portName;
    final serialSettings =
        '${state.baudRate} · ${state.dataBits}'
        '${switch (state.parity) {
          UiParity.none => 'N',
          UiParity.odd => 'O',
          UiParity.even => 'E',
        }}${state.stopBits}';

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
              message: '$status\n${state.portName} · $serialSettings',
              child: Text(
                '${portText.isEmpty ? l10n.noPortSelected : portText}'
                '${portText.isEmpty ? '' : ' · $serialSettings'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message:
                  '$statsText\n${l10n.trafficStats(state.rxBytes, state.txBytes)}'
                  '\n${l10n.trafficStatsTooltip}',
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

String _formatIecBytes(num bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.round()} ${units[unit]}'
      : '${value.toStringAsFixed(1)} ${units[unit]}';
}
