import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../../utils/connection_status.dart';

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
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            backgroundColor: isConnected ? colors.error : colors.primary,
            foregroundColor: isConnected ? colors.onError : colors.onPrimary,
          ),
          onPressed:
              isBusy || (!disconnect && (selectedPort == null || isUnavailable))
              ? null
              : () =>
                    disconnect ? controller.disconnect() : controller.connect(),
          icon: isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  disconnect ? Icons.link_off : Icons.link,
                  size: 18,
                ),
          label: Text(
            isBusy
                ? connectionStatusLabel(connectionState, l10n)
                : disconnect
                ? l10n.disconnect
                : l10n.connect,
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
    if (ports.isEmpty) {
      return InputDecorator(
        decoration: _denseInputDecoration(context, l10n.portName),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.noPortsFound),
            if (isReconnecting && selectedPort != null)
              Text(
                '${l10n.reconnecting}: $selectedPort',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (isUnavailable)
              Text(
                '${l10n.unavailable}: $selectedPort',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }

    final entries = <DropdownMenuEntry<String>>[
      ...ports.map(
        (port) => DropdownMenuEntry<String>(value: port, label: port),
      ),
    ];

    return DropdownMenu<String>(
      key: ValueKey('${ports.join('\u0000')}\u0001$selectedPort'),
      expandedInsets: EdgeInsets.zero,
      initialSelection: selectedPort,
      dropdownMenuEntries: entries,
      onSelected: isDisabled ? null : onSelected,
      errorText: isReconnecting && selectedPort != null
          ? '${l10n.reconnecting}: $selectedPort'
          : isUnavailable
          ? '${l10n.unavailable}: $selectedPort'
          : null,
      label: Text(AppLocalizations.of(context).portName),
      enabled: !isDisabled && entries.isNotEmpty,
    );
  }

  InputDecoration _denseInputDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12.0,
        vertical: 14.0,
      ),
    );
  }
}
