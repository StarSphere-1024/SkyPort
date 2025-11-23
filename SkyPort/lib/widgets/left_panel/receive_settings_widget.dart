import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial_provider.dart';
import '../../l10n/app_localizations.dart';
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
          onChanged: (v) => notifier.setHexDisplay(v),
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
        _buildReceiveModeSelector(context, settings, notifier),
        const SizedBox(height: 8),
        _buildReceiveModeContent(context, settings, notifier),
      ],
    );
  }

  Widget _buildReceiveModeSelector(
    BuildContext context,
    UiSettings settings,
    UiSettingsNotifier notifier,
  ) {
    final currentValue = settings.hexDisplay ? false : settings.lineMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context).receiveMode,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
        SizedBox(
          width: 160, // Provide sufficient width for DropdownMenu
          child: DropdownMenu<bool>(
            initialSelection: currentValue,
            dropdownMenuEntries: [
              DropdownMenuEntry<bool>(
                value: false,
                label: AppLocalizations.of(context).blockReceiveMode,
                trailingIcon: Tooltip(
                  message: AppLocalizations.of(context).blockReceiveDescription,
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
              DropdownMenuEntry<bool>(
                value: true,
                label: AppLocalizations.of(context).lineReceiveMode,
                enabled:
                    !settings.hexDisplay, // Disable line mode in HEX display
                trailingIcon: Tooltip(
                  message: AppLocalizations.of(context).lineReceiveDescription,
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
            onSelected: (bool? value) {
              if (value != null && (!settings.hexDisplay || value == false)) {
                notifier.setReceiveMode(value);
              }
            },
            enableFilter: false,
            enableSearch: false,
            textStyle: Theme.of(context).textTheme.bodyMedium,
            menuStyle: MenuStyle(
              backgroundColor: WidgetStateProperty.all(
                Theme.of(context).colorScheme.surface,
              ),
              surfaceTintColor: WidgetStateProperty.all(
                Theme.of(context).colorScheme.surfaceTint,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiveModeContent(
    BuildContext context,
    UiSettings settings,
    UiSettingsNotifier notifier,
  ) {
    final currentMode = settings.hexDisplay ? false : settings.lineMode;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: currentMode
          ? const SizedBox.shrink() // Line mode: no additional content
          : _buildBlockIntervalInput(
              context, settings, notifier), // Block mode: show interval input
    );
  }

  Widget _buildBlockIntervalInput(
    BuildContext context,
    UiSettings settings,
    UiSettingsNotifier notifier,
  ) {
    return Container(
      key: const ValueKey('blockInterval'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context).blockInterval,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          SizedBox(
            width: 80,
            child: TextField(
              controller: TextEditingController(
                  text: settings.blockIntervalMs.toString())
                ..selection = TextSelection.fromPosition(TextPosition(
                    offset: settings.blockIntervalMs.toString().length)),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: AppInputDecorations.dense(
                context: context,
                label: '',
                suffixText: 'ms',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
              onSubmitted: (value) {
                final v = int.tryParse(value);
                if (v != null && v > 0) {
                  notifier.setFrameIntervalMs(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
