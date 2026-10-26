import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../shared/compact_switch.dart';
import '../../utils/error_messages.dart';
import '../shared/error_notice.dart';
import '../shared/dropdown_builders.dart';

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
          icon: Icons.code_rounded,
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
            Icon(
              Icons.autorenew_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.autoSend,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
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
        if (settings.autoSendError != null) ...[
          Text(
            l10n.autoSendPaused(localizedError(l10n, settings.autoSendError!)),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: () => showErrorDetails(context, settings.autoSendError!),
            child: Text(l10n.diagnosticDetails),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.keyboard_return_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.newlineMode,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            SizedBox(
              width: 145,
              child: DropdownBuilders.buildDropdown<UiNewline>(
                context: context,
                label: l10n.newlineMode,
                showLabel: false,
                enabled: !settings.hexSend,
                initialSelection: settings.appendNewline
                    ? settings.newline
                    : UiNewline.none,
                entries: const [
                  DropdownMenuEntry(value: UiNewline.none, label: 'None'),
                  DropdownMenuEntry(value: UiNewline.lf, label: r'LF (\n)'),
                  DropdownMenuEntry(value: UiNewline.cr, label: r'CR (\r)'),
                  DropdownMenuEntry(
                    value: UiNewline.crlf,
                    label: r'CRLF (\r\n)',
                  ),
                ],
                onSelected: settings.hexSend
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.setSendSettings(
                            appendNewline: value != UiNewline.none,
                            newline: value == UiNewline.none ? null : value,
                          );
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
