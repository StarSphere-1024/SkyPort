import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';
import '../shared/compact_switch.dart';
import '../shared/input_decorations.dart';

class ReceiveSettingsWidget extends ConsumerWidget {
  const ReceiveSettingsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(serialConnectionProvider
        .select((c) => c.status == ConnectionStatus.connected));
    final isBusy = ref.watch(serialConnectionProvider.select((c) =>
        c.status == ConnectionStatus.connecting ||
        c.status == ConnectionStatus.disconnecting));

    return _buildReceiveSettings(context, ref, isConnected, isBusy);
  }

  Widget _buildReceiveSettings(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
    bool isBusy,
  ) {
    final settings = ref.watch(uiSettingsProvider);
    final notifier = ref.read(uiSettingsProvider.notifier);

    return Column(
      children: [
        CompactSwitch(
          label: AppLocalizations.of(context).hexDisplay,
          value: settings.hexDisplay,
          onChanged:
              (isConnected || isBusy) ? null : (v) => notifier.setHexDisplay(v),
        ),
        CompactSwitch(
          label: AppLocalizations.of(context).showTimestamp,
          value: settings.showTimestamp,
          onChanged: (v) => notifier.setShowTimestamp(v),
        ),
        CompactSwitch(
          label: AppLocalizations.of(context).showSent,
          value: settings.showSent,
          onChanged: (v) => notifier.setShowSent(v),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(AppLocalizations.of(context).autoFrameBreak,
                style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    enabled: settings.autoFrameBreak,
                    controller: TextEditingController(
                        text: settings.autoFrameBreakMs.toString())
                      ..selection = TextSelection.fromPosition(TextPosition(
                          offset: settings.autoFrameBreakMs.toString().length)),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: AppInputDecorations.dense(
                      context: context,
                      label: '',
                      suffixText: 'ms',
                      filled: true,
                      fillColor: settings.autoFrameBreak
                          ? Theme.of(context).colorScheme.surface
                          : Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    onSubmitted: (value) {
                      final v = int.tryParse(value);
                      if (v != null && v > 0) {
                        notifier.setAutoFrameBreakMs(v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 5),
                Switch(
                  value: settings.autoFrameBreak,
                  onChanged: (v) => notifier.setAutoFrameBreak(v),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
