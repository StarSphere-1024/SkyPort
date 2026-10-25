import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/ui_state.dart';

String connectionStatusLabel(UiConnection connection, AppLocalizations l10n) =>
    switch (connection) {
      UiConnection.connected => l10n.connected,
      UiConnection.connecting => l10n.connecting,
      UiConnection.reconfiguring => l10n.applyingConfiguration,
      UiConnection.reconnecting => l10n.reconnecting,
      UiConnection.disconnecting || UiConnection.closing => l10n.disconnecting,
      UiConnection.disconnected || UiConnection.closed => l10n.disconnected,
    };

Color connectionStatusColor(UiConnection connection, ThemeData theme) {
  final light = theme.brightness == Brightness.light;
  return switch (connection) {
    UiConnection.connected =>
      light ? Colors.green.shade800 : Colors.green.shade300,
    UiConnection.reconfiguring =>
      light ? Colors.blue.shade700 : Colors.blue.shade300,
    UiConnection.connecting ||
    UiConnection.reconnecting ||
    UiConnection.disconnecting ||
    UiConnection.closing => theme.colorScheme.tertiary,
    UiConnection.disconnected ||
    UiConnection.closed => theme.colorScheme.outline,
  };
}
