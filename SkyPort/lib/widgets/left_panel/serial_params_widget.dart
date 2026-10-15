import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../shared/dropdown_builders.dart';

class SerialParamsWidget extends ConsumerWidget {
  const SerialParamsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReconfiguring = ref.watch(
      uiControllerProvider.select(
        (state) => state.connection == UiConnection.reconfiguring,
      ),
    );

    return _buildSerialParamsGrid(context, ref, isReconfiguring);
  }

  Widget _buildSerialParamsGrid(
    BuildContext context,
    WidgetRef ref,
    bool isReconfiguring,
  ) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          baudRate: state.baudRate,
          dataBits: state.dataBits,
          parity: state.parity,
          stopBits: state.stopBits,
        ),
      ),
    );
    final controller = ref.read(uiControllerProvider.notifier);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  DropdownBuilders.buildNumericDropdown<int>(
                    initialSelection: state.baudRate,
                    entries: DropdownBuilders.createEntries([
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
                      921600,
                    ], (e) => e.toString()),
                    label: AppLocalizations.of(context).baudRate,
                    // 修改立即生效，不需要禁用
                    onSelected: (v) =>
                        v != null ? controller.setBaudRate(v) : null,
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
                initialSelection: state.dataBits,
                entries: DropdownBuilders.createEntries([
                  8,
                  7,
                  6,
                  5,
                ], (e) => e.toString()),
                label: AppLocalizations.of(context).dataBits,
                onSelected: (v) => v != null ? controller.setDataBits(v) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownMenu<UiParity>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: state.parity,
                dropdownMenuEntries: [
                  DropdownMenuEntry<UiParity>(
                    value: UiParity.none,
                    label: AppLocalizations.of(context).parityNone,
                  ),
                  DropdownMenuEntry<UiParity>(
                    value: UiParity.odd,
                    label: AppLocalizations.of(context).parityOdd,
                  ),
                  DropdownMenuEntry<UiParity>(
                    value: UiParity.even,
                    label: AppLocalizations.of(context).parityEven,
                  ),
                ],
                onSelected: (value) {
                  if (value != null) controller.setParity(value);
                },
                label: Text(AppLocalizations.of(context).parity),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownBuilders.buildNumericDropdown<int>(
                initialSelection: state.stopBits,
                entries: DropdownBuilders.createEntries([
                  1,
                  2,
                ], (e) => e.toString()),
                label: AppLocalizations.of(context).stopBits,
                onSelected: (v) => v != null ? controller.setStopBits(v) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
