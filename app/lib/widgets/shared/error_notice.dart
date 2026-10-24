import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/error_messages.dart';

void showErrorNotice(BuildContext context, Object error, {String? message}) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      persist: false,
      showCloseIcon: true,
      content: SelectableText(message ?? localizedError(l10n, error)),
      action: SnackBarAction(
        label: l10n.diagnosticDetails,
        onPressed: () => showErrorDetails(context, error),
      ),
    ),
  );
}

Future<void> showErrorDetails(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.diagnosticDetails),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: SelectableText(errorDiagnostics(error)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
