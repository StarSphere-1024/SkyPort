import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class LeftPanel extends ConsumerWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final isConnected = connection.status == ConnectionStatus.connected;
    final isBusy = connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.disconnecting;

    Widget connectButtonChild;
    switch (connection.status) {
      case ConnectionStatus.connected:
        connectButtonChild = Text(AppLocalizations.of(context).close);
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        connectButtonChild = SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            // Use appropriate contrasting color from ColorScheme
            color: isConnected
                ? Theme.of(context).colorScheme.onError
                : Theme.of(context).colorScheme.onPrimary,
          ),
        );
        break;
      case ConnectionStatus.disconnected:
        connectButtonChild = Text(AppLocalizations.of(context).open);
    }

    return Padding(
      // Use 16dp outer padding to align with design blueprint spacing system
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).serialPortSettings,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, child) {
                              final availablePorts =
                                  ref.watch(availablePortsProvider);
                              final serialConfig =
                                  ref.watch(serialConfigProvider);

                              return availablePorts.when(
                                data: (ports) {
                                  var selectedPort = serialConfig?.portName;

                                  // If selectedPort is null, try to select first available
                                  if (selectedPort == null &&
                                      ports.isNotEmpty) {
                                    selectedPort = ports.first;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      ref
                                          .read(serialConfigProvider.notifier)
                                          .setPort(selectedPort!);
                                    });
                                  }

                                  final dropdownItems = ports
                                      .map((port) => DropdownMenuItem<String>(
                                            value: port,
                                            child: Text(
                                              port,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ))
                                      .toList();

                                  final isUnavailable = selectedPort != null &&
                                      !ports.contains(selectedPort);

                                  // If we have a selected port but it's not in the list, add it as unavailable
                                  if (isUnavailable) {
                                    dropdownItems.add(DropdownMenuItem<String>(
                                      value: selectedPort,
                                      child: Text(
                                        selectedPort,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ));
                                  }

                                  if (dropdownItems.isEmpty) {
                                    return InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: AppLocalizations.of(context)
                                            .portName,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12.0,
                                                vertical: 16.0),
                                        helperText: ' ',
                                      ),
                                      child: Text(AppLocalizations.of(context)
                                          .noPortsFound),
                                    );
                                  }

                                  return DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText:
                                          AppLocalizations.of(context).portName,
                                      border: const OutlineInputBorder(),
                                      errorText: isUnavailable
                                          ? AppLocalizations.of(context)
                                              .unavailable
                                          : null,
                                      helperText: isUnavailable ? null : ' ',
                                    ),
                                    initialValue: selectedPort,
                                    items: dropdownItems,
                                    onChanged: (isConnected || isBusy)
                                        ? null
                                        : (String? value) {
                                            if (value != null) {
                                              ref
                                                  .read(serialConfigProvider
                                                      .notifier)
                                                  .setPort(value);
                                            }
                                          },
                                  );
                                },
                                loading: () => InputDecorator(
                                  decoration: InputDecoration(
                                    labelText:
                                        AppLocalizations.of(context).portName,
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 16.0),
                                    helperText: ' ',
                                  ),
                                  child: Text(AppLocalizations.of(context)
                                      .loadingPorts),
                                ),
                                error: (err, stack) => InputDecorator(
                                  decoration: InputDecoration(
                                    labelText:
                                        AppLocalizations.of(context).portName,
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 16.0),
                                    helperText: ' ',
                                  ),
                                  child: Text(AppLocalizations.of(context)
                                      .errorLoadingPorts),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: FilledButton(
                            onPressed: isBusy
                                ? null
                                : () {
                                    if (isConnected) {
                                      ref
                                          .read(
                                              serialConnectionProvider.notifier)
                                          .disconnect();
                                    } else {
                                      final availablePorts = ref
                                              .read(availablePortsProvider)
                                              .asData
                                              ?.value ??
                                          [];
                                      final selectedPort = ref
                                          .read(serialConfigProvider)
                                          ?.portName;

                                      if (selectedPort == null ||
                                          !availablePorts
                                              .contains(selectedPort)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                              "${AppLocalizations.of(context).unavailable}: $selectedPort"),
                                        ));
                                        return;
                                      }
                                      ref
                                          .read(
                                              serialConnectionProvider.notifier)
                                          .connect();
                                    }
                                  },
                            style: isConnected
                                ? FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                    foregroundColor:
                                        Theme.of(context).colorScheme.onError,
                                  )
                                : FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                            child: connectButtonChild,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Consumer(
                      builder: (context, ref, child) {
                        final serialConfig = ref.watch(serialConfigProvider);
                        return GridView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 2.8,
                          ),
                          children: [
                            DropdownButtonFormField<int>(
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context).baudRate,
                                border: const OutlineInputBorder(),
                              ),
                              initialValue: serialConfig?.baudRate ?? 9600,
                              items: const [
                                DropdownMenuItem(
                                    value: 1200, child: Text('1200')),
                                DropdownMenuItem(
                                    value: 2400, child: Text('2400')),
                                DropdownMenuItem(
                                    value: 4800, child: Text('4800')),
                                DropdownMenuItem(
                                    value: 9600, child: Text('9600')),
                                DropdownMenuItem(
                                    value: 19200, child: Text('19200')),
                                DropdownMenuItem(
                                    value: 38400, child: Text('38400')),
                                DropdownMenuItem(
                                    value: 57600, child: Text('57600')),
                                DropdownMenuItem(
                                    value: 115200, child: Text('115200')),
                                DropdownMenuItem(
                                    value: 230400, child: Text('230400')),
                                DropdownMenuItem(
                                    value: 460800, child: Text('460800')),
                                DropdownMenuItem(
                                    value: 921600, child: Text('921600')),
                              ],
                              onChanged: (isConnected || isBusy)
                                  ? null
                                  : (int? value) {
                                      if (value != null) {
                                        ref
                                            .read(serialConfigProvider.notifier)
                                            .setBaudRate(value);
                                      }
                                    },
                            ),
                            DropdownButtonFormField<int>(
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context).dataBits,
                                border: const OutlineInputBorder(),
                              ),
                              initialValue: serialConfig?.dataBits ?? 8,
                              items: const [
                                DropdownMenuItem(value: 8, child: Text('8')),
                                DropdownMenuItem(value: 7, child: Text('7')),
                                DropdownMenuItem(value: 6, child: Text('6')),
                                DropdownMenuItem(value: 5, child: Text('5')),
                              ],
                              onChanged: (isConnected || isBusy)
                                  ? null
                                  : (int? value) {
                                      if (value != null) {
                                        ref
                                            .read(serialConfigProvider.notifier)
                                            .setDataBits(value);
                                      }
                                    },
                            ),
                            DropdownButtonFormField<int>(
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context).parity,
                                border: const OutlineInputBorder(),
                              ),
                              initialValue: serialConfig?.parity ?? 0,
                              items: [
                                DropdownMenuItem(
                                    value: 0,
                                    child: Text(AppLocalizations.of(context)
                                        .parityNone)),
                                DropdownMenuItem(
                                    value: 1,
                                    child: Text(AppLocalizations.of(context)
                                        .parityOdd)),
                                DropdownMenuItem(
                                    value: 2,
                                    child: Text(AppLocalizations.of(context)
                                        .parityEven)),
                              ],
                              onChanged: (isConnected || isBusy)
                                  ? null
                                  : (int? value) {
                                      if (value != null) {
                                        ref
                                            .read(serialConfigProvider.notifier)
                                            .setParity(value);
                                      }
                                    },
                            ),
                            DropdownButtonFormField<int>(
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context).stopBits,
                                border: const OutlineInputBorder(),
                              ),
                              initialValue: serialConfig?.stopBits ?? 1,
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1')),
                                DropdownMenuItem(value: 2, child: Text('2')),
                              ],
                              onChanged: (isConnected || isBusy)
                                  ? null
                                  : (int? value) {
                                      if (value != null) {
                                        ref
                                            .read(serialConfigProvider.notifier)
                                            .setStopBits(value);
                                      }
                                    },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).receiveSettings,
                        style: Theme.of(context).textTheme.titleLarge),
                    Consumer(
                      builder: (context, ref, child) {
                        final settings = ref.watch(uiSettingsProvider);
                        return SwitchListTile(
                          title: Text(AppLocalizations.of(context).hexDisplay),
                          value: settings.hexDisplay,
                          onChanged: (isConnected || isBusy)
                              ? null
                              : (value) {
                                  ref
                                      .read(uiSettingsProvider.notifier)
                                      .setHexDisplay(value);
                                },
                        );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final settings = ref.watch(uiSettingsProvider);
                        return SwitchListTile(
                          title:
                              Text(AppLocalizations.of(context).showTimestamp),
                          value: settings.showTimestamp,
                          onChanged: (value) {
                            ref
                                .read(uiSettingsProvider.notifier)
                                .setShowTimestamp(value);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(dataLogProvider.notifier).clear();
                        },
                        child:
                            Text(AppLocalizations.of(context).clearReceiveArea),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).sendSettings,
                        style: Theme.of(context).textTheme.titleLarge),
                    Consumer(
                      builder: (context, ref, child) {
                        final settings = ref.watch(uiSettingsProvider);
                        return SwitchListTile(
                          title: Text(AppLocalizations.of(context).hexSend),
                          value: settings.hexSend,
                          onChanged: (isConnected || isBusy)
                              ? null
                              : (value) {
                                  ref
                                      .read(uiSettingsProvider.notifier)
                                      .setHexSend(value);
                                },
                        );
                      },
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
