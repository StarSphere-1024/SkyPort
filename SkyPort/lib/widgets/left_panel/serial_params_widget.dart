import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial/serial_port_manager.dart';
import '../../models/connection_status.dart';
import '../../l10n/app_localizations.dart';
import '../shared/dropdown_builders.dart';

class SerialParamsWidget extends ConsumerWidget {
  const SerialParamsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serialPortManagerProvider);
    final manager = ref.read(serialPortManagerProvider.notifier);
    final isReconfiguring = state.isReconciling;

    return _buildSerialParamsGrid(context, ref, isReconfiguring);
  }

  Widget _buildSerialParamsGrid(
    BuildContext context,
    WidgetRef ref,
    bool isReconfiguring,
  ) {
    final state = ref.watch(serialPortManagerProvider);
    final manager = ref.read(serialPortManagerProvider.notifier);
    final targetConfig = state.targetConfig;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  DropdownBuilders.buildNumericDropdown<int>(
                    initialSelection: targetConfig.baudRate,
                    entries: DropdownBuilders.createEntries(
                      [
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
                      ],
                      (e) => e.toString(),
                    ),
                    label: AppLocalizations.of(context).baudRate,
                    // 修改立即生效，不需要禁用
                    onSelected: (v) => v != null
                        ? manager.setBaudRate(v)
                        : null,
                  ),
                  // 调和时显示小加载圈
                  if (isReconfiguring)
                    Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownBuilders.buildNumericDropdown<int>(
                initialSelection: targetConfig.dataBits,
                entries: DropdownBuilders.createEntries(
                  [8, 7, 6, 5],
                  (e) => e.toString(),
                ),
                label: AppLocalizations.of(context).dataBits,
                onSelected: (v) => v != null
                    ? manager.setDataBits(v)
                    : null,
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
                initialSelection: targetConfig.parity,
                dropdownMenuEntries: [
                  DropdownMenuEntry<int>(
                      value: 0, label: AppLocalizations.of(context).parityNone),
                  DropdownMenuEntry<int>(
                      value: 1, label: AppLocalizations.of(context).parityOdd),
                  DropdownMenuEntry<int>(
                      value: 2, label: AppLocalizations.of(context).parityEven),
                ],
                onSelected: (v) => v != null
                    ? manager.setParity(v)
                    : null,
                label: Text(AppLocalizations.of(context).parity),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownBuilders.buildNumericDropdown<int>(
                initialSelection: targetConfig.stopBits,
                entries: DropdownBuilders.createEntries(
                  [1, 2],
                  (e) => e.toString(),
                ),
                label: AppLocalizations.of(context).stopBits,
                onSelected: (v) => v != null
                    ? manager.setStopBits(v)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
