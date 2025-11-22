import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class LeftPanel extends ConsumerWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serialConnectionProvider);
    final isConnected = connection.status == ConnectionStatus.connected;
    final isBusy = connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.disconnecting;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(25),
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                      context, AppLocalizations.of(context).serialPortSettings),
                  const SizedBox(height: 12),
                  _buildPortSelectionRow(context, ref, isConnected, isBusy),
                  const SizedBox(height: 12),
                  _buildSerialParamsGrid(context, ref, isConnected, isBusy),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                      context, AppLocalizations.of(context).receiveSettings),
                  const SizedBox(height: 8),
                  _buildReceiveSettings(context, ref, isConnected, isBusy),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                      context, AppLocalizations.of(context).sendSettings),
                  const SizedBox(height: 8),
                  _buildSendSettings(context, ref, isConnected, isBusy),
                ],
              ),
            ),
          ),
          _buildBottomAction(context, ref),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Widget _buildPortSelectionRow(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
    bool isBusy,
  ) {
    final connection = ref.watch(serialConnectionProvider);

    Widget connectButtonChild;
    switch (connection.status) {
      case ConnectionStatus.connected:
        connectButtonChild = Text(AppLocalizations.of(context).close);
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        connectButtonChild = SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: isConnected
                ? Theme.of(context).colorScheme.onError
                : Theme.of(context).colorScheme.onPrimary,
          ),
        );
        break;
      case ConnectionStatus.disconnected:
        connectButtonChild = Text(AppLocalizations.of(context).open);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final availablePorts = ref.watch(availablePortsProvider);
              final serialConfig = ref.watch(serialConfigProvider);

              return availablePorts.when(
                data: (ports) {
                  var selectedPort = serialConfig?.portName;
                  if (selectedPort == null && ports.isNotEmpty) {
                    selectedPort = ports.first;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref
                          .read(serialConfigProvider.notifier)
                          .setPort(selectedPort!);
                    });
                  }

                  final dropdownItems = ports
                      .map((port) => DropdownMenuItem<String>(
                            value: port,
                            child: Text(port, overflow: TextOverflow.ellipsis),
                          ))
                      .toList();

                  final isUnavailable =
                      selectedPort != null && !ports.contains(selectedPort);

                  if (isUnavailable) {
                    dropdownItems.add(DropdownMenuItem<String>(
                      value: selectedPort,
                      child: Text(
                        selectedPort,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ));
                  }

                  if (dropdownItems.isEmpty) {
                    return InputDecorator(
                      decoration: _denseInputDecoration(
                          context, AppLocalizations.of(context).portName),
                      child: Text(
                        AppLocalizations.of(context).noPortsFound,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  return DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: selectedPort,
                    dropdownMenuEntries: ports
                        .map((port) => DropdownMenuEntry<String>(
                              value: port,
                              label: port,
                            ))
                        .toList(),
                    onSelected: (isConnected || isBusy)
                        ? null
                        : (String? value) {
                            if (value != null) {
                              ref
                                  .read(serialConfigProvider.notifier)
                                  .setPort(value);
                            }
                          },
                    errorText: isUnavailable
                        ? AppLocalizations.of(context).unavailable
                        : null,
                    label: Text(AppLocalizations.of(context).portName),
                  );
                },
                loading: () => DropdownMenu<String>(
                  enabled: false,
                  label: Text(AppLocalizations.of(context).loadingPorts),
                  dropdownMenuEntries: [],
                ),
                error: (err, stack) => DropdownMenu<String>(
                  enabled: false,
                  label: Text(AppLocalizations.of(context).errorLoadingPorts),
                  dropdownMenuEntries: [],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          child: FilledButton(
            onPressed: isBusy
                ? null
                : () {
                    if (isConnected) {
                      ref.read(serialConnectionProvider.notifier).disconnect();
                    } else {
                      final availablePorts =
                          ref.read(availablePortsProvider).asData?.value ?? [];
                      final selectedPort =
                          ref.read(serialConfigProvider)?.portName;

                      if (selectedPort == null ||
                          !availablePorts.contains(selectedPort)) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              "${AppLocalizations.of(context).unavailable}: $selectedPort"),
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }
                      ref.read(serialConnectionProvider.notifier).connect();
                    }
                  },
            child: connectButtonChild,
          ),
        ),
      ],
    );
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
        _buildCompactSwitch(
          context,
          label: AppLocalizations.of(context).hexDisplay,
          value: settings.hexDisplay,
          onChanged:
              (isConnected || isBusy) ? null : (v) => notifier.setHexDisplay(v),
        ),
        _buildCompactSwitch(
          context,
          label: AppLocalizations.of(context).showTimestamp,
          value: settings.showTimestamp,
          onChanged: (v) => notifier.setShowTimestamp(v),
        ),
        _buildCompactSwitch(
          context,
          label: AppLocalizations.of(context).showSent,
          value: settings.showSent,
          onChanged: (v) => notifier.setShowSent(v),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _buildCompactSwitch(
                context,
                label: AppLocalizations.of(context).autoFrameBreak,
                value: settings.autoFrameBreak,
                onChanged: (v) => notifier.setAutoFrameBreak(v),
                padding: EdgeInsets.zero,
              ),
            ),
            if (settings.autoFrameBreak) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: TextEditingController(
                      text: settings.autoFrameBreakMs.toString())
                    ..selection = TextSelection.fromPosition(TextPosition(
                        offset: settings.autoFrameBreakMs.toString().length)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _denseInputDecoration(context, "ms"),
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
            ],
          ],
        ),
      ],
    );
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
        _buildCompactSwitch(
          context,
          label: l10n.hexSend,
          value: settings.hexSend,
          onChanged:
              (isConnected || isBusy) ? null : (v) => notifier.setHexSend(v),
        ),
        const SizedBox(height: 8),
        _buildCompactSwitch(
          context,
          label: l10n.appendNewline,
          value: settings.appendNewline,
          onChanged: settings.hexSend
              ? null
              : (v) {
                  notifier.setAppendNewline(v);
                },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownMenu<int>(
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
          ],
        ),
      ],
    );
  }

  Widget _buildBottomAction(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            ref.read(dataLogProvider.notifier).clear();
          },
          icon: const Icon(Icons.delete_outline, size: 24),
          label: Text(AppLocalizations.of(context).clearReceiveArea),
        ),
      ),
    );
  }

  Widget _buildCompactSwitch(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
    EdgeInsetsGeometry? padding,
  }) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  InputDecoration _denseInputDecoration(BuildContext context, String label,
      {String? errorText}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
      errorText: errorText,
    );
  }
}
