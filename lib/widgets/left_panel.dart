import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';
import 'left_panel/port_selection_widget.dart';
import 'left_panel/serial_params_widget.dart';
import 'left_panel/receive_settings_widget.dart';
import 'left_panel/send_settings_widget.dart';

class LeftPanel extends ConsumerWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  const PortSelectionWidget(),
                  const SizedBox(height: 12),
                  const SerialParamsWidget(),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                      context, AppLocalizations.of(context).receiveSettings),
                  const SizedBox(height: 8),
                  const ReceiveSettingsWidget(),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                      context, AppLocalizations.of(context).sendSettings),
                  const SizedBox(height: 8),
                  const SendSettingsWidget(),
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
}
