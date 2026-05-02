import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/connection_status.dart';
import '../../providers/serial/serial_port_manager.dart';

class PortSelectionWidget extends ConsumerWidget {
  const PortSelectionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serialPortManagerProvider);
    final manager = ref.read(serialPortManagerProvider.notifier);

    final connectionState = state.connection.state;
    final isConnected = connectionState == ConnectionState.connected;
    final isBusy = state.isBusy;
    final ports = state.availablePorts;
    final selectedPort = state.targetConfig.portName.isEmpty
        ? null
        : state.targetConfig.portName;
    final isUnavailable = selectedPort != null && !ports.contains(selectedPort);

    Widget connectButtonChild;
    switch (connectionState) {
      case ConnectionState.connected:
        connectButtonChild = Text(AppLocalizations.of(context).close);
        break;
      case ConnectionState.reconnecting:
      case ConnectionState.disconnected:
        connectButtonChild = Text(AppLocalizations.of(context).open);
        break;
      case ConnectionState.connecting:
      case ConnectionState.disconnecting:
      case ConnectionState.reconfiguring:
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
                manager.setPortName(value);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          child: FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  final colors = Theme.of(context).colorScheme;
                  if (states.contains(WidgetState.disabled)) {
                    return null;
                  }
                  return isConnected ? colors.error : colors.primary;
                },
              ),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  final colors = Theme.of(context).colorScheme;
                  if (states.contains(WidgetState.disabled)) {
                    return null;
                  }
                  return isConnected ? colors.onError : colors.onPrimary;
                },
              ),
            ),
            onPressed: isBusy
                ? null
                : () async {
                    if (isConnected ||
                        connectionState == ConnectionState.reconnecting) {
                      await manager.disconnect();
                      return;
                    }

                    if (selectedPort == null || !ports.contains(selectedPort)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "${AppLocalizations.of(context).unavailable}: $selectedPort",
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return;
                    }

                    await manager.connect();
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
        (port) => DropdownMenuEntry<String>(
          value: port,
          label: port,
        ),
      ),
    ];

    if (isUnavailable && selectedPort != null) {
      entries.add(
        DropdownMenuEntry<String>(
          value: selectedPort,
          label: selectedPort,
        ),
      );
    }

    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      initialSelection: selectedPort ?? (ports.isNotEmpty ? ports.first : null),
      dropdownMenuEntries: entries,
      onSelected: isDisabled ? null : onSelected,
      errorText:
          isUnavailable ? AppLocalizations.of(context).unavailable : null,
      label: Text(AppLocalizations.of(context).portName),
      enabled: entries.isNotEmpty,
    );
  }

  InputDecoration _denseInputDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
    );
  }
}
