import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

class LogExportService {
  static Future<void> exportLogs({
    required BuildContext context,
    required String defaultPath,
    required String portName,
    required Future<void> Function(String path) export,
  }) async {
    final l10n = AppLocalizations.of(context);
    final safePortName = portName.isEmpty
        ? 'serial'
        : portName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final destination = await getSaveLocation(
      suggestedName: '${safePortName}_$date.txt',
      initialDirectory: defaultPath.isEmpty ? null : defaultPath,
      acceptedTypeGroups: [
        XTypeGroup(label: l10n.exportLogs, extensions: const ['txt']),
      ],
    );
    if (destination == null || !context.mounted) return;
    try {
      await export(destination.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.logsExportedTo}${destination.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${l10n.exportFailed}$error')));
      }
    }
  }
}
