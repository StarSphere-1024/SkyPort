import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../../utils/constants.dart';
import '../shared/compact_switch.dart';

class SendSettingsWidget extends ConsumerWidget {
  const SendSettingsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      uiControllerProvider.select(
        (state) => (
          hexSend: state.hexSend,
          autoSendEnabled: state.autoSendEnabled,
          autoSendIntervalMs: state.autoSendIntervalMs,
          autoSendError: state.autoSendError,
          appendNewline: state.appendNewline,
          newline: state.newline,
        ),
      ),
    );
    final controller = ref.read(uiControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        CompactSwitch(
          label: l10n.hexSend,
          value: settings.hexSend,
          onChanged: (value) => controller.setSendSettings(
            hex: value,
            input: ref.read(autoSendDraftProvider.notifier).forMode(value),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l10n.autoSend, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: (settings.autoSendIntervalMs / 1000)
                        .toString(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                      border: UnderlineInputBorder(),
                    ),
                    textAlign: TextAlign.center,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null;
                      final interval = double.tryParse(value);
                      if (interval == null ||
                          interval < 0.01 ||
                          interval > 60) {
                        return '';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final interval = double.tryParse(value);
                      if (interval != null &&
                          interval >= 0.01 &&
                          interval <= 60) {
                        controller.setSendSettings(
                          intervalMs: (interval * 1000).round(),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  l10n.secondsUnit,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 5),
                Switch(
                  value: settings.autoSendEnabled,
                  onChanged: (v) => controller.setSendSettings(
                    enabled: v,
                    input: v ? ref.read(autoSendDraftProvider) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (settings.autoSendError != null)
          Text(
            l10n.autoSendPaused(settings.autoSendError!.message),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              l10n.appendNewline,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: SkyPortConstants.intervalInputWidth.toDouble(),
                  child: DropdownMenu<UiNewline>(
                    enabled: settings.appendNewline && !settings.hexSend,
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: settings.newline,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry<UiNewline>(
                        value: UiNewline.lf,
                        label: r"\n",
                      ),
                      DropdownMenuEntry<UiNewline>(
                        value: UiNewline.cr,
                        label: r"\r",
                      ),
                      DropdownMenuEntry<UiNewline>(
                        value: UiNewline.crlf,
                        label: r"\r\n",
                      ),
                    ],
                    onSelected: settings.hexSend
                        ? null
                        : (value) {
                            if (value != null) {
                              controller.setSendSettings(newline: value);
                            }
                          },
                    label: Text(l10n.newlineMode),
                  ),
                ),
                const SizedBox(width: 5),
                Switch(
                  value: settings.appendNewline,
                  onChanged: settings.hexSend
                      ? null
                      : (value) =>
                            controller.setSendSettings(appendNewline: value),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
