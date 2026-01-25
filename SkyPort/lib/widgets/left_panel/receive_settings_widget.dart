import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/serial/serial_connection_provider.dart';
import '../../providers/serial/ui_settings_provider.dart';
import '../../models/connection_status.dart';
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
}
