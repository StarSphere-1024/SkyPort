import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      final suggestedName = '${date}_$safePortName.txt';
      String? destination;
      if (Theme.of(context).platform == TargetPlatform.android) {
        final temporary = await Directory.systemTemp.createTemp(
          'skyport-export-',
        );
        try {
          final path = '${temporary.path}/$suggestedName';
          await export(path);
          if (!context.mounted) return;
          destination = await const MethodChannel('skyport/android')
              .invokeMethod<String>('exportFile', {
                'path': path,
                'suggestedName': suggestedName,
              });
        } finally {
          await temporary.delete(recursive: true);
        }
      } else {
        final selected = await getSaveLocation(
          suggestedName: suggestedName,
          initialDirectory: defaultPath.isEmpty ? null : defaultPath,
          acceptedTypeGroups: [
            XTypeGroup(label: l10n.exportLogs, extensions: const ['txt']),
          ],
        );
        if (selected == null || !context.mounted) return;
        await export(selected.path);
        destination = selected.path;
      }
      if (destination == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.logsExportedTo}$destination')),
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
