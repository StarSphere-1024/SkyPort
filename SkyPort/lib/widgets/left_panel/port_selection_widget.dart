import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial_provider.dart';
import '../../l10n/app_localizations.dart';

class PortSelectionWidget extends ConsumerWidget {
  const PortSelectionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(serialConnectionProvider
        .select((c) => c.status == ConnectionStatus.connected));
    final isBusy = ref.watch(serialConnectionProvider.select((c) =>
        c.status == ConnectionStatus.connecting ||
        c.status == ConnectionStatus.disconnecting));

    return _buildPortSelectionRow(context, ref, isConnected, isBusy);
  }

  Widget _buildPortSelectionRow(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
    bool isBusy,
  ) {
    final connectionStatus =
        ref.watch(serialConnectionProvider.select((c) => c.status));

    Widget connectButtonChild;
    switch (connectionStatus) {
      case ConnectionStatus.connected:
        connectButtonChild = Text(AppLocalizations.of(context).close);
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
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
      case ConnectionStatus.disconnected:
        connectButtonChild = Text(AppLocalizations.of(context).open);
        break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final availablePorts = ref.watch(availablePortsProvider);
              final serialConfig = ref.watch(serialConfigProvider);

              return availablePorts.when(
                data: (ports) {
                  var selectedPort = serialConfig?.portName;
                  if (selectedPort == null && ports.isNotEmpty) {
                    selectedPort = ports.first;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref
                          .read(serialConfigProvider.notifier)
                          .setPort(selectedPort!);
                    });
                  }

                  final dropdownItems = ports
                      .map((port) => DropdownMenuItem<String>(
                            value: port,
                            child: Text(port, overflow: TextOverflow.ellipsis),
                          ))
                      .toList();

                  final isUnavailable =
                      selectedPort != null && !ports.contains(selectedPort);

                  if (isUnavailable) {
                    dropdownItems.add(DropdownMenuItem<String>(
                      value: selectedPort,
                      child: Text(
                        selectedPort,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ));
                  }

                  if (dropdownItems.isEmpty) {
                    return InputDecorator(
                      decoration: _denseInputDecoration(
                          context, AppLocalizations.of(context).portName),
                      child: Text(
                        AppLocalizations.of(context).noPortsFound,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  return DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: selectedPort,
                    dropdownMenuEntries: ports
                        .map((port) => DropdownMenuEntry<String>(
                              value: port,
                              label: port,
                            ))
                        .toList(),
                    onSelected: (isConnected || isBusy)
                        ? null
                        : (String? value) {
                            if (value != null) {
                              ref
                                  .read(serialConfigProvider.notifier)
                                  .setPort(value);
                            }
                          },
                    errorText: isUnavailable
                        ? AppLocalizations.of(context).unavailable
                        : null,
                    label: Text(AppLocalizations.of(context).portName),
                  );
                },
                loading: () => DropdownMenu<String>(
                  enabled: false,
                  label: Text(AppLocalizations.of(context).loadingPorts),
                  dropdownMenuEntries: [],
                ),
                error: (err, stack) => DropdownMenu<String>(
                  enabled: false,
                  label: Text(AppLocalizations.of(context).errorLoadingPorts),
                  dropdownMenuEntries: [],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          child: FilledButton(
            onPressed: isBusy
                ? null
                : () {
                    if (isConnected) {
                      ref.read(serialConnectionProvider.notifier).disconnect();
                    } else {
                      final availablePorts =
                          ref.read(availablePortsProvider).asData?.value ?? [];
                      final selectedPort =
                          ref.read(serialConfigProvider)?.portName;

                      if (selectedPort == null ||
                          !availablePorts.contains(selectedPort)) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              "${AppLocalizations.of(context).unavailable}: $selectedPort"),
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }
                      ref.read(serialConnectionProvider.notifier).connect();
                    }
                  },
            child: connectButtonChild,
          ),
        ),
      ],
    );
  }

  InputDecoration _denseInputDecoration(BuildContext context, String label,
      {String? errorText}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
      errorText: errorText,
    );
  }
}
