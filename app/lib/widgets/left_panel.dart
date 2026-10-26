import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/ui_controller.dart';
import '../utils/connection_status.dart';
import 'left_panel/port_selection_widget.dart';
import 'left_panel/receive_settings_widget.dart';
import 'left_panel/send_settings_widget.dart';
import 'left_panel/serial_params_widget.dart';
import 'shared/settings_section.dart';

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // The section's 12 px inset preserves the original 16 px control margins.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            title: AppLocalizations.of(context).serialPortSettings,
            icon: Icons.usb_rounded,
            trailing: const _ConnectionStatus(),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  children: [
                    PortSelectionWidget(),
                    SizedBox(height: 12),
                    SerialParamsWidget(),
                  ],
                ),
              ),
            ],
          ),
          SettingsSection(
            title: AppLocalizations.of(context).receiveSettings,
            icon: Icons.desktop_windows_outlined,
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: ReceiveSettingsWidget(),
              ),
            ],
          ),
          SettingsSection(
            title: AppLocalizations.of(context).sendSettings,
            icon: Icons.send_rounded,
            children: const [
              Padding(padding: EdgeInsets.all(12), child: SendSettingsWidget()),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatus extends ConsumerWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(
      uiControllerProvider.select((state) => state.connection),
    );
    final theme = Theme.of(context);
    final label = connectionStatusLabel(
      connection,
      AppLocalizations.of(context),
    );
    final color = connectionStatusColor(connection, theme);
    return Semantics(
      liveRegion: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
