import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/serial/ui_settings_provider.dart';
import '../shared/compact_switch.dart';

class ReceiveSettingsWidget extends ConsumerWidget {
  const ReceiveSettingsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
