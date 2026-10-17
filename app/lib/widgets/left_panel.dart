import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'left_panel/port_selection_widget.dart';
import 'left_panel/receive_settings_widget.dart';
import 'left_panel/send_settings_widget.dart';
import 'left_panel/serial_params_widget.dart';

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            context,
            AppLocalizations.of(context).serialPortSettings,
          ),
          const SizedBox(height: 12),
          const PortSelectionWidget(),
          const SizedBox(height: 12),
          const SerialParamsWidget(),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _buildSectionTitle(
            context,
            AppLocalizations.of(context).receiveSettings,
          ),
          const SizedBox(height: 8),
          const ReceiveSettingsWidget(),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _buildSectionTitle(
            context,
            AppLocalizations.of(context).sendSettings,
          ),
          const SizedBox(height: 8),
          const SendSettingsWidget(),
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
}
