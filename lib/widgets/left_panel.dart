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
                        child: DropdownMenu<String>(
                          enabled: !isConnected,
                          label: const Text('Port Name'),
                          initialSelection: serialConfig?.portName,
                          onSelected: (String? value) {
                            if (value != null) {
                              ref
                                  .read(serialConfigProvider.notifier)
                                  .setPort(value);
                            }
                          },
                          dropdownMenuEntries: availablePorts.when(
                            data: (ports) => ports
                                .map((port) => DropdownMenuEntry<String>(
                                      value: port,
                                      label: port,
                                    ))
                                .toList(),
                            loading: () => [],
                            error: (err, stack) => [],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.refresh(availablePortsProvider),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownMenu<int>(
                    enabled: !isConnected,
                    label: const Text('Baud Rate'),
                    initialSelection: serialConfig?.baudRate ?? 9600,
                    onSelected: (int? value) {
                      if (value != null) {
                        ref
                            .read(serialConfigProvider.notifier)
                            .setBaudRate(value);
                      }
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 9600, label: '9600'),
                      DropdownMenuEntry(value: 19200, label: '19200'),
                      DropdownMenuEntry(value: 38400, label: '38400'),
                      DropdownMenuEntry(value: 57600, label: '57600'),
                      DropdownMenuEntry(value: 115200, label: '115200'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownMenu<int>(
                    enabled: !isConnected,
                    label: const Text('Data Bits'),
                    initialSelection: serialConfig?.dataBits ?? 8,
                    onSelected: (int? value) {
                      if (value != null) {
                        ref
                            .read(serialConfigProvider.notifier)
                            .setDataBits(value);
                      }
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 8, label: '8'),
                      DropdownMenuEntry(value: 7, label: '7'),
                      DropdownMenuEntry(value: 6, label: '6'),
                      DropdownMenuEntry(value: 5, label: '5'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownMenu<int>(
                    enabled: !isConnected,
                    label: const Text('Parity'),
                    initialSelection: serialConfig?.parity ?? 0,
                    onSelected: (int? value) {
                      if (value != null) {
                        ref.read(serialConfigProvider.notifier).setParity(value);
                      }
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 0, label: 'None'),
                      DropdownMenuEntry(value: 1, label: 'Odd'),
                      DropdownMenuEntry(value: 2, label: 'Even'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownMenu<int>(
                    enabled: !isConnected,
                    label: const Text('Stop Bits'),
                    initialSelection: serialConfig?.stopBits ?? 1,
                    onSelected: (int? value) {
                      if (value != null) {
                        ref
                            .read(serialConfigProvider.notifier)
                            .setStopBits(value);
                      }
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 1, label: '1'),
                      DropdownMenuEntry(value: 2, label: '2'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (isConnected) {
                          ref.read(serialConnectionProvider.notifier).close();
                        } else {
                          ref.read(serialConnectionProvider.notifier).open();
                        }
                      },
                      style: isConnected
                          ? FilledButton.styleFrom(
                              backgroundColor: Colors.red)
                          : null,
                      child: Text(isConnected ? 'Close' : 'Open'),
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
                  Text('Receive Settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  SwitchListTile(
                    title: const Text('Hex Display'),
                    value: ref.watch(settingsProvider).hexDisplay,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setHexDisplay(value);
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
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setHexSend(value);
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
