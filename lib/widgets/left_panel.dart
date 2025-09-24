import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';

class LeftPanel extends ConsumerWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serialConfig = ref.watch(serialConfigProvider);
    final connection = ref.watch(serialConnectionProvider);
    final isConnected = connection.status == ConnectionStatus.connected;
    final availablePorts = ref.watch(availablePortsProvider);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
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
                          child: availablePorts.when(
                            data: (ports) {
                              // Ensure the selected port is valid, otherwise default to null (or the first port)
                              final selectedPort = (serialConfig?.portName !=
                                          null &&
                                      ports.contains(serialConfig?.portName))
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
                                onChanged: isConnected
                                    ? null
                                    : (String? value) {
                                        if (value != null) {
                                          ref
                                              .read(
                                                  serialConfigProvider.notifier)
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
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          onPressed: () {
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
                          child: Text(isConnected ? 'Close' : 'Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GridView(
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
                            DropdownMenuItem(value: 9600, child: Text('9600')),
                            DropdownMenuItem(
                                value: 115200, child: Text('115200')),
                          ],
                          onChanged: isConnected
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
                          onChanged: isConnected
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
                          onChanged: isConnected
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
                          onChanged: isConnected
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
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: Container(),
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
                    Text('Receive Settings',
                        style: Theme.of(context).textTheme.titleLarge),
                    SwitchListTile(
                      title: const Text('Hex Display'),
                      value: ref.watch(settingsProvider).hexDisplay,
                      onChanged: isConnected
                          ? null
                          : (value) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setHexDisplay(value);
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
                    SwitchListTile(
                      title: const Text('Hex Send'),
                      value: ref.watch(settingsProvider).hexSend,
                      onChanged: isConnected
                          ? null
                          : (value) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setHexSend(value);
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
