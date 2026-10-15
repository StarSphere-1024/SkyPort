import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';

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

    Widget connectButtonChild;
    switch (connectionState) {
      case UiConnection.connected:
        connectButtonChild = Text(AppLocalizations.of(context).close);
        break;
      case UiConnection.reconnecting:
      case UiConnection.disconnected:
      case UiConnection.closed:
        connectButtonChild = Text(AppLocalizations.of(context).open);
        break;
      case UiConnection.connecting:
      case UiConnection.disconnecting:
      case UiConnection.reconfiguring:
      case UiConnection.closing:
        connectButtonChild = SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: isConnected
                ? Theme.of(context).colorScheme.onError
                : Theme.of(context).colorScheme.onPrimary,
          ),
        );
        break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _buildPortDropdown(
            context: context,
            ports: ports,
            selectedPort: selectedPort,
            isUnavailable: isUnavailable,
            isDisabled: isConnected || isBusy,
            onSelected: (value) {
              if (value != null) {
                controller.setPort(value);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          child: FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                final colors = Theme.of(context).colorScheme;
                if (states.contains(WidgetState.disabled)) {
                  return null;
                }
                return isConnected ? colors.error : colors.primary;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                final colors = Theme.of(context).colorScheme;
                if (states.contains(WidgetState.disabled)) {
                  return null;
                }
                return isConnected ? colors.onError : colors.onPrimary;
              }),
            ),
            onPressed: isBusy || (!isConnected && selectedPort == null)
                ? null
                : () async {
                    if (isConnected ||
                        connectionState == UiConnection.reconnecting) {
                      await controller.disconnect();
                      return;
                    }

                    await controller.connect();
                  },
            child: connectButtonChild,
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
    required bool isDisabled,
    required ValueChanged<String?> onSelected,
  }) {
    if (ports.isEmpty && selectedPort == null) {
      return InputDecorator(
        decoration: _denseInputDecoration(
          context,
          AppLocalizations.of(context).portName,
        ),
        child: Text(
          AppLocalizations.of(context).noPortsFound,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final entries = <DropdownMenuEntry<String>>[
      ...ports.map(
        (port) => DropdownMenuEntry<String>(value: port, label: port),
      ),
    ];

    if (isUnavailable && selectedPort != null) {
      entries.add(
        DropdownMenuEntry<String>(value: selectedPort, label: selectedPort),
      );
    }

    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      initialSelection: selectedPort,
      dropdownMenuEntries: entries,
      onSelected: isDisabled ? null : onSelected,
      errorText: isUnavailable
          ? AppLocalizations.of(context).unavailable
          : null,
      label: Text(AppLocalizations.of(context).portName),
      enabled: entries.isNotEmpty,
    );
  }

  InputDecoration _denseInputDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12.0,
        vertical: 14.0,
      ),
    );
  }
}
