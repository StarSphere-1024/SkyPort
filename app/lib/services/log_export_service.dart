import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../utils/error_messages.dart';
import '../widgets/shared/error_notice.dart';

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
    final date = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    try {
      final destination = await getSaveLocation(
        suggestedName: '${date}_$safePortName.txt',
        initialDirectory: defaultPath.isEmpty ? null : defaultPath,
        acceptedTypeGroups: [
          XTypeGroup(label: l10n.exportLogs, extensions: const ['txt']),
        ],
      );
      if (destination == null || !context.mounted) return;
      await export(destination.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.logsExportedTo}${destination.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showErrorNotice(
          context,
          error,
          message: l10n.exportFailed(localizedError(l10n, error)),
        );
      }
    }
  }
}
