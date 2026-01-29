import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial/serial_connection_provider.dart';
import '../../providers/serial/ui_settings_provider.dart';
import '../../models/connection_status.dart';
import '../../models/ui_settings.dart';
import '../../l10n/app_localizations.dart';
import '../shared/compact_switch.dart';

class SendSettingsWidget extends ConsumerWidget {
  const SendSettingsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(serialConnectionProvider
        .select((c) => c.status == ConnectionStatus.connected));
    final isBusy = ref.watch(serialConnectionProvider.select((c) =>
        c.status == ConnectionStatus.connecting ||
        c.status == ConnectionStatus.disconnecting));

    return _buildSendSettings(context, ref, isConnected, isBusy);
  }

  Widget _buildSendSettings(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
    bool isBusy,
  ) {
    final settings = ref.watch(uiSettingsProvider);
    final notifier = ref.read(uiSettingsProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        CompactSwitch(
          label: l10n.hexSend,
          value: settings.hexSend,
          onChanged: (v) => notifier.setHexSend(v),
        ),
        const SizedBox(height: 8),
        // Auto-Send Section
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l10n.autoSend,
                style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: (settings.autoSendIntervalMs / 1000).toString(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                      border: UnderlineInputBorder(),
                    ),
                    textAlign: TextAlign.center,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null;
                      final interval = double.tryParse(value);
                      if (interval == null || interval < 0.01 || interval > 60) {
                        return '';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final interval = double.tryParse(value);
                      if (interval != null && interval >= 0.01 && interval <= 60) {
                        notifier.setAutoSendIntervalMs((interval * 1000).round());
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
                  onChanged: (v) => notifier.setAutoSendEnabled(v),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l10n.appendNewline,
                style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: DropdownMenu<int>(
                    enabled: settings.appendNewline,
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: settings.newlineMode.index,
                    dropdownMenuEntries: [
                      DropdownMenuEntry<int>(
                        value: 0,
                        label: r"\n",
                      ),
                      DropdownMenuEntry<int>(
                        value: 1,
                        label: r"\r",
                      ),
                      DropdownMenuEntry<int>(
                        value: 2,
                        label: r"\r\n",
                      ),
                    ],
                    onSelected: (!settings.appendNewline || settings.hexSend)
                        ? null
                        : (v) {
                            if (v == null) return;
                            switch (v) {
                              case 0:
                                notifier.setNewlineMode(NewlineMode.lf);
                                break;
                              case 1:
                                notifier.setNewlineMode(NewlineMode.cr);
                                break;
                              case 2:
                                notifier.setNewlineMode(NewlineMode.crlf);
                                break;
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
                      : (v) => notifier.setAppendNewline(v),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
