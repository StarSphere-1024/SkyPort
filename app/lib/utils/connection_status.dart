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
