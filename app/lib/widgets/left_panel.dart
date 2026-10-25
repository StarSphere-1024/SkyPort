import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
      // The card's 12 px inset preserves the original 16 px control margins.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            title: AppLocalizations.of(context).serialPortSettings,
            icon: Icons.usb_rounded,
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
