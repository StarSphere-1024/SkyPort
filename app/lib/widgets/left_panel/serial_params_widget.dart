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
          flowControl: state.flowControl,
          dataBits: state.dataBits,
          parity: state.parity,
          stopBits: state.stopBits,
        ),
      ),
    );
    final controller = ref.read(uiControllerProvider.notifier);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 250;
            return Row(
              children: [
                Expanded(
                  flex: compact ? 5 : 1,
                  child: DropdownBuilders.buildDropdown<int>(
                    context: context,
                    initialSelection: state.baudRate,
                    label: AppLocalizations.of(context).baudRate,
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
                    ], (value) => value.toString()),
                    onSelected: (value) =>
                        value != null ? controller.setBaudRate(value) : null,
                  ),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  flex: compact ? 4 : 1,
                  child: Tooltip(
                    message: state.flowControl == UiFlowControl.software
                        ? AppLocalizations.of(
                            context,
                          ).flowControlSoftwareWarning
                        : '',
                    child: DropdownBuilders.buildDropdown<UiFlowControl>(
                      context: context,
                      menuKey: ValueKey(Localizations.localeOf(context)),
                      initialSelection: state.flowControl,
                      label: AppLocalizations.of(context).flowControl,
                      entries: [
                        DropdownMenuEntry(
                          value: UiFlowControl.none,
                          label: AppLocalizations.of(context).flowControlNone,
                        ),
                        DropdownMenuEntry(
                          value: UiFlowControl.hardware,
                          label: AppLocalizations.of(
                            context,
                          ).flowControlHardware,
                        ),
                        DropdownMenuEntry(
                          value: UiFlowControl.software,
                          label: AppLocalizations.of(
                            context,
                          ).flowControlSoftware,
                        ),
                      ],
                      onSelected: (value) => value != null
                          ? controller.setFlowControl(value)
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (isReconfiguring)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 40, top: 4),
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
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownBuilders.buildDropdown<int>(
                context: context,
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
            const SizedBox(width: 12),
            Expanded(
              child: DropdownBuilders.buildDropdown<int>(
                context: context,
                initialSelection: state.stopBits,
                entries: DropdownBuilders.createEntries([
                  1,
                  2,
                ], (e) => e.toString()),
                label: AppLocalizations.of(context).stopBits,
                onSelected: (v) => v != null ? controller.setStopBits(v) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownBuilders.buildDropdown<UiParity>(
                context: context,
                menuKey: ValueKey(Localizations.localeOf(context)),
                initialSelection: state.parity,
                entries: [
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
                label: AppLocalizations.of(context).parity,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
