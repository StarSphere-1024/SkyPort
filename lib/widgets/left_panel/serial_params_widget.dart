import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class SerialParamsWidget extends ConsumerWidget {
  const SerialParamsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(serialConnectionProvider
        .select((c) => c.status == ConnectionStatus.connected));
    final isBusy = ref.watch(serialConnectionProvider.select((c) =>
        c.status == ConnectionStatus.connecting ||
        c.status == ConnectionStatus.disconnecting));

    return _buildSerialParamsGrid(context, ref, isConnected, isBusy);
  }

  Widget _buildSerialParamsGrid(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
    bool isBusy,
  ) {
    final serialConfig = ref.watch(serialConfigProvider);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownMenu<int>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: serialConfig?.baudRate ?? 9600,
                dropdownMenuEntries: [
                  1200,
                  2400,
                  4800,
                  9600,
                  19200,
                  38400,
                  57600,
                  115200,
                  230400,
                  460800,
                  921600
                ]
                    .map((e) => DropdownMenuEntry<int>(
                          value: e,
                          label: e.toString(),
                        ))
                    .toList(),
                onSelected: (isConnected || isBusy)
                    ? null
                    : (v) => v != null
                        ? ref.read(serialConfigProvider.notifier).setBaudRate(v)
                        : null,
                label: Text(AppLocalizations.of(context).baudRate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownMenu<int>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: serialConfig?.dataBits ?? 8,
                dropdownMenuEntries: [8, 7, 6, 5]
                    .map((e) => DropdownMenuEntry<int>(
                          value: e,
                          label: e.toString(),
                        ))
                    .toList(),
                onSelected: (isConnected || isBusy)
                    ? null
                    : (v) => v != null
                        ? ref.read(serialConfigProvider.notifier).setDataBits(v)
                        : null,
                label: Text(AppLocalizations.of(context).dataBits),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownMenu<int>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: serialConfig?.parity ?? 0,
                dropdownMenuEntries: [
                  DropdownMenuEntry<int>(
                      value: 0, label: AppLocalizations.of(context).parityNone),
                  DropdownMenuEntry<int>(
                      value: 1, label: AppLocalizations.of(context).parityOdd),
                  DropdownMenuEntry<int>(
                      value: 2, label: AppLocalizations.of(context).parityEven),
                ],
                onSelected: (isConnected || isBusy)
                    ? null
                    : (v) => v != null
                        ? ref.read(serialConfigProvider.notifier).setParity(v)
                        : null,
                label: Text(AppLocalizations.of(context).parity),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownMenu<int>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: serialConfig?.stopBits ?? 1,
                dropdownMenuEntries: [
                  DropdownMenuEntry<int>(value: 1, label: '1'),
                  DropdownMenuEntry<int>(value: 2, label: '2'),
                ],
                onSelected: (isConnected || isBusy)
                    ? null
                    : (v) => v != null
                        ? ref.read(serialConfigProvider.notifier).setStopBits(v)
                        : null,
                label: Text(AppLocalizations.of(context).stopBits),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
