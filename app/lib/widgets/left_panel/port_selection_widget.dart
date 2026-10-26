import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../../utils/connection_status.dart';
import '../shared/dropdown_builders.dart';

class PortSelectionWidget extends ConsumerWidget {
  const PortSelectionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          connection: state.connection,
          ports: state.ports,
          portName: state.portName,
        ),
      ),
    );
    final controller = ref.read(uiControllerProvider.notifier);

    final connectionState = state.connection;
    final isConnected = connectionState == UiConnection.connected;
    final isBusy =
        connectionState == UiConnection.connecting ||
        connectionState == UiConnection.disconnecting ||
        connectionState == UiConnection.reconfiguring ||
        connectionState == UiConnection.closing ||
        connectionState == UiConnection.closed;
    final ports = state.ports;
    final selectedPort = state.portName.isEmpty ? null : state.portName;
    final isUnavailable =
        !isConnected && selectedPort != null && !ports.contains(selectedPort);

    final disconnect =
        isConnected || connectionState == UiConnection.reconnecting;
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildPortDropdown(
            context: context,
            ports: ports,
            selectedPort: selectedPort,
            isUnavailable: isUnavailable,
            isReconnecting: connectionState == UiConnection.reconnecting,
            isDisabled: isConnected || isBusy,
            onSelected: (value) {
              if (value != null) controller.setPort(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: isConnected ? colors.error : colors.primary,
              foregroundColor: isConnected ? colors.onError : colors.onPrimary,
            ),
            onPressed:
                isBusy ||
                    (!disconnect && (selectedPort == null || isUnavailable))
                ? null
                : () => disconnect
                      ? controller.disconnect()
                      : controller.connect(),
            icon: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(disconnect ? Icons.link_off : Icons.link, size: 18),
            label: Text(
              isBusy
                  ? connectionStatusLabel(connectionState, l10n)
                  : disconnect
                  ? l10n.disconnect
                  : l10n.connect,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortDropdown({
    required BuildContext context,
    required List<String> ports,
    required String? selectedPort,
    required bool isUnavailable,
    required bool isReconnecting,
    required bool isDisabled,
    required ValueChanged<String?> onSelected,
  }) {
    final l10n = AppLocalizations.of(context);

    final entries = <DropdownMenuEntry<String>>[
      ...ports.map(
        (port) => DropdownMenuEntry<String>(value: port, label: port),
      ),
    ];

    return DropdownBuilders.buildDropdown<String>(
      context: context,
      menuKey: ValueKey('${ports.join('\u0000')}\u0001$selectedPort'),
      initialSelection: selectedPort,
      entries: entries,
      onSelected: isDisabled ? null : onSelected,
      hintText: ports.isEmpty ? l10n.noPortsFound : null,
      errorText: isReconnecting && selectedPort != null
          ? '${l10n.reconnecting}: $selectedPort'
          : isUnavailable
          ? '${l10n.unavailable}: $selectedPort'
          : null,
      label: l10n.portName,
      enabled: !isDisabled && entries.isNotEmpty,
    );
  }
}
