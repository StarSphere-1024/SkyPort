import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';

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
        connectButtonChild = const Text('Close');
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        connectButtonChild = const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        );
        break;
      case ConnectionStatus.disconnected:
        connectButtonChild = const Text('Open');
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
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
                    Text('Serial Port Settings',
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
                                  // Ensure the selected port is valid, otherwise default to null (or the first port)
                                  final selectedPort = (serialConfig
                                                  ?.portName !=
                                              null &&
                                          ports
                                              .contains(serialConfig?.portName))
                                      ? serialConfig?.portName
                                      : (ports.isNotEmpty ? ports.first : null);

                                  // If the config is not set and we have a port, set it.
                                  if (selectedPort != null &&
                                      serialConfig?.portName == null) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      ref
                                          .read(serialConfigProvider.notifier)
                                          .setPort(selectedPort);
                                    });
                                  }

                                  if (ports.isEmpty) {
                                    return const InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Port Name',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12.0, vertical: 16.0),
                                      ),
                                      child: Text('No ports found'),
                                    );
                                  }

                                  return DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Port Name',
                                      border: OutlineInputBorder(),
                                    ),
                                    initialValue: selectedPort,
                                    items: ports
                                        .map((port) => DropdownMenuItem<String>(
                                              value: port,
                                              child: Text(
                                                port,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ))
                                        .toList(),
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
                                loading: () => const InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Port Name',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 16.0),
                                  ),
                                  child: Text('Loading ports...'),
                                ),
                                error: (err, stack) => const InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Port Name',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 16.0),
                                  ),
                                  child: Text('Error loading ports'),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          onPressed: isBusy
                              ? null
                              : () {
                                  if (isConnected) {
                                    ref
                                        .read(serialConnectionProvider.notifier)
                                        .close();
                                  } else {
                                    ref
                                        .read(serialConnectionProvider.notifier)
                                        .open();
                                  }
                                },
                          style: isConnected
                              ? FilledButton.styleFrom(
                                  backgroundColor: Colors.red)
                              : null,
                          child: connectButtonChild,
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
                              decoration: const InputDecoration(
                                labelText: 'Baud Rate',
                                border: OutlineInputBorder(),
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
                              decoration: const InputDecoration(
                                labelText: 'Data Bits',
                                border: OutlineInputBorder(),
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
                              decoration: const InputDecoration(
                                labelText: 'Parity',
                                border: OutlineInputBorder(),
                              ),
                              initialValue: serialConfig?.parity ?? 0,
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('None')),
                                DropdownMenuItem(value: 1, child: Text('Odd')),
                                DropdownMenuItem(value: 2, child: Text('Even')),
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
                              decoration: const InputDecoration(
                                labelText: 'Stop Bits',
                                border: OutlineInputBorder(),
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
                    Text('Receive Settings',
                        style: Theme.of(context).textTheme.titleLarge),
                    Consumer(
                      builder: (context, ref, child) {
                        final settings = ref.watch(settingsProvider);
                        return SwitchListTile(
                          title: const Text('Hex Display'),
                          value: settings.hexDisplay,
                          onChanged: (isConnected || isBusy)
                              ? null
                              : (value) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setHexDisplay(value);
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
                        child: const Text('Clear Receive Area'),
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
                    Text('Send Settings',
                        style: Theme.of(context).textTheme.titleLarge),
                    Consumer(
                      builder: (context, ref, child) {
                        final settings = ref.watch(settingsProvider);
                        return SwitchListTile(
                          title: const Text('Hex Send'),
                          value: settings.hexSend,
                          onChanged: (isConnected || isBusy)
                              ? null
                              : (value) {
                                  ref
                                      .read(settingsProvider.notifier)
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
