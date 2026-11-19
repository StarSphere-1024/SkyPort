import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';
import '../../utils/connection_status.dart';

class PortSelectionWidget extends ConsumerStatefulWidget {
  const PortSelectionWidget({super.key});

  @override
  ConsumerState<PortSelectionWidget> createState() =>
      _PortSelectionWidgetState();
}

class _PortSelectionWidgetState extends ConsumerState<PortSelectionWidget> {
  String? _pendingPort;
  bool _switching = false;

  Future<void> _switchPort(String port) async {
    setState(() => _switching = true);
    try {
      await ref.read(uiControllerProvider.notifier).switchPort(port);
    } finally {
      if (mounted) {
        setState(() {
          _switching = false;
          _pendingPort = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          connection: state.connection,
          ports: state.ports,
          portName: state.portName,
          appliedConfig: state.appliedConfig,
        ),
      ),
    );
    final controller = ref.read(uiControllerProvider.notifier);
    ref.listen(uiControllerProvider.select((state) => state.connection), (
      _,
      connection,
    ) {
      if (connection == UiConnection.disconnected && !_switching) {
        setState(() => _pendingPort = null);
      }
    });

    final connectionState = state.connection;
    final isConnected = connectionState == UiConnection.connected;
    final isBusy =
        _switching ||
        connectionState == UiConnection.connecting ||
        connectionState == UiConnection.disconnecting ||
        connectionState == UiConnection.reconfiguring ||
        connectionState == UiConnection.closing ||
        connectionState == UiConnection.closed;
    final connectedPort = isConnected ? state.appliedConfig?.portName : null;
    final ports = [
      if (connectedPort != null)
        state.ports.firstWhere(
          (port) => port.portName == connectedPort,
          orElse: () => UiPort(portName: connectedPort),
        ),
      for (final port in state.ports)
        if (port.portName != connectedPort) port,
    ];
    final hasConnection =
        isConnected || connectionState == UiConnection.reconnecting;
    final selectedPort = hasConnection
        ? _pendingPort ?? state.portName
        : state.portName;
    final switchingPort =
        hasConnection && selectedPort != (connectedPort ?? state.portName);
    final isUnavailable =
        selectedPort.isNotEmpty &&
        !ports.any((port) => port.portName == selectedPort);
    final disconnect = hasConnection && !switchingPort;
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildPortDropdown(
              context: context,
              ports: ports,
              selectedPort: selectedPort,
              connectedPort: connectedPort,
              isUnavailable: isUnavailable,
              isReconnecting: connectionState == UiConnection.reconnecting,
              isDisabled: isBusy,
              onSelected: (value) {
                if (value == null) return;
                if (hasConnection) {
                  setState(() => _pendingPort = value);
                } else {
                  controller.setPort(value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            // Transient status labels must leave room for the port selector.
            constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: disconnect ? colors.error : colors.primary,
                  foregroundColor: disconnect
                      ? colors.onError
                      : colors.onPrimary,
                ),
                onPressed:
                    isBusy ||
                        (!disconnect && (selectedPort.isEmpty || isUnavailable))
                    ? null
                    : () => switchingPort
                          ? _switchPort(selectedPort)
                          : disconnect
                          ? controller.disconnect()
                          : controller.connect(),
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        switchingPort
                            ? Icons.swap_horiz
                            : disconnect
                            ? Icons.link_off
                            : Icons.link,
                        size: 18,
                      ),
                label: Text(
                  isBusy
                      ? _switching
                            ? l10n.applyingConfiguration
                            : connectionStatusLabel(connectionState, l10n)
                      : switchingPort
                      ? l10n.switchPort
                      : disconnect
                      ? l10n.disconnect
                      : l10n.connect,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortDropdown({
    required BuildContext context,
    required List<UiPort> ports,
    required String? selectedPort,
    required String? connectedPort,
    required bool isUnavailable,
    required bool isReconnecting,
    required bool isDisabled,
    required ValueChanged<String?> onSelected,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      gapPadding: 0,
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    String title(UiPort port) => [
      port.portName,
      if (port.product?.trim().isNotEmpty ?? false) port.product!.trim(),
    ].join(' · ');
    String details(UiPort port) => [
      if (port.manufacturer?.trim().isNotEmpty ?? false)
        port.manufacturer!.trim(),
      if (port.vid != null && port.pid != null)
        'VID:PID ${port.vid!.toRadixString(16).padLeft(4, '0').toUpperCase()}:'
            '${port.pid!.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      if (port.serialNumber?.trim().isNotEmpty ?? false)
        '${l10n.serialNumber}: ${port.serialNumber!.trim()}',
    ].join(' · ');
    final hasSelection = ports.any((port) => port.portName == selectedPort);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.portName,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            enabled: !isDisabled && ports.isNotEmpty,
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            contentPadding: EdgeInsets.zero,
            errorText: isReconnecting && selectedPort != null
                ? '${l10n.reconnecting}: $selectedPort'
                : isUnavailable
                ? '${l10n.unavailable}: $selectedPort'
                : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: hasSelection ? selectedPort : null,
              isExpanded: true,
              isDense: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              menuWidth: math.min(360, MediaQuery.sizeOf(context).width - 32),
              menuMaxHeight: 360,
              itemHeight: null,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              style: theme.textTheme.bodyMedium,
              hint: Text(
                ports.isEmpty
                    ? l10n.noPortsFound
                    : selectedPort ?? l10n.portName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: isDisabled ? null : onSelected,
              selectedItemBuilder: (context) => [
                for (final port in ports)
                  Tooltip(
                    message: [
                      title(port),
                      if (details(port).isNotEmpty) details(port),
                    ].join('\n'),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final painter = TextPainter(
                            text: TextSpan(
                              text: title(port),
                              style: theme.textTheme.bodyMedium,
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                            maxLines: 1,
                          )..layout();
                          final fits = painter.width <= constraints.maxWidth;
                          painter.dispose();
                          return Text(
                            fits ? title(port) : port.portName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                  ),
              ],
              items: [
                for (final port in ports)
                  DropdownMenuItem(
                    value: port.portName,
                    child: Tooltip(
                      message: [
                        title(port),
                        if (details(port).isNotEmpty) details(port),
                      ].join('\n'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title(port),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (port.portName == connectedPort) ...[
                            const SizedBox(width: 8),
                            Text(
                              l10n.connected,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
