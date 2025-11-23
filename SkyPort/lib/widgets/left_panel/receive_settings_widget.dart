import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial_provider.dart';
import '../../l10n/app_localizations.dart';
import '../shared/compact_switch.dart';

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
        _buildReceiveModeSelector(context, settings, notifier),
        const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _buildReceiveModeSelector(
    BuildContext context,
    UiSettings settings,
    UiSettingsNotifier notifier,
  ) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context).receiveMode,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            IconButton(
              icon: Icon(Icons.help_outline, size: 16),
              onPressed: null,
              tooltip: settings.hexDisplay
                  ? AppLocalizations.of(context).receiveModeTooltipHex
                  : AppLocalizations.of(context).receiveModeTooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const Spacer(),
            SegmentedButton<ReceiveMode>(
              segments: [
                ButtonSegment<ReceiveMode>(
                  value: ReceiveMode.line,
                  label: Text(AppLocalizations.of(context).lineModeLabel),
                  icon: Icon(Icons.wrap_text),
                  enabled: !settings.hexDisplay,
                ),
                ButtonSegment<ReceiveMode>(
                  value: ReceiveMode.block,
                  label: Text(AppLocalizations.of(context).blockModeLabel),
                  icon: Icon(Icons.timer_outlined),
                ),
              ],
              selected: {settings.receiveMode},
              onSelectionChanged: (Set<ReceiveMode> selected) {
                if (selected.isNotEmpty) {
                  final mode = selected.first;
                  if (mode == ReceiveMode.line && settings.hexDisplay) {
                    // Don't allow line mode in hex display
                    return;
                  }
                  notifier.setReceiveMode(mode);
                }
              },
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: Theme.of(context).colorScheme.surface,
                selectedBackgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                selectedForegroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: settings.receiveMode == ReceiveMode.block
              ? Column(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context).timeoutLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: TextEditingController(
                                text: settings.blockIntervalMs.toString())
                              ..selection = TextSelection.fromPosition(
                                  TextPosition(
                                      offset: settings.blockIntervalMs
                                          .toString()
                                          .length)),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                              suffixText: 'ms',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
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
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
