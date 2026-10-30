import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';
import 'shared/error_notice.dart';

Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  UpdateService? updateService,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      UpdatePanel._details(release: release, updateService: updateService),
);

class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key, this.updateService}) : initialRelease = null;

  const UpdatePanel._details({required AppRelease release, this.updateService})
    : initialRelease = release;

  final UpdateService? updateService;
  final AppRelease? initialRelease;

  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  late final UpdateService _service = widget.updateService ?? UpdateService();
  late final bool _ownsService = widget.updateService == null;
  AppRelease? _release;
  String? _directory;
  String? _filePath;
  bool _checking = false;
  bool _downloading = false;
  bool _validating = false;
  bool _cancelled = false;
  bool _cancelRequested = false;
  int _received = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _release = widget.initialRelease;
  }

  @override
  void dispose() {
    if (_downloading) _service.cancelDownload();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      final release = await _service.check(version);
      if (!mounted) return;
      setState(() => _checking = false);
      if (release == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).updateUpToDate)),
        );
      } else {
        await showUpdateDialog(context, release, updateService: _service);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
      });
      _showFailure(error);
    }
  }

  Future<void> _download(UpdateAsset asset) async {
    setState(() {
      _downloading = true;
      _validating = false;
      _cancelled = false;
      _cancelRequested = false;
      _filePath = null;
      _received = 0;
      _total = asset.size;
    });
    try {
      late final Directory directory;
      try {
        directory =
            await getDownloadsDirectory() ??
            await getApplicationSupportDirectory();
      } catch (error) {
        throw UpdateException(UpdateFailure.fileAccess, error.toString());
      }
      if (!mounted) return;
      if (_cancelRequested) {
        throw const UpdateException(UpdateFailure.cancelled);
      }
      setState(() => _directory = directory.path);
      final file = await _service.download(
        asset,
        directory,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _validating = total > 0 && received >= total;
          });
        },
      );
      if (mounted) {
        setState(() {
          _filePath = file.path;
          _directory = file.parent.path;
          _downloading = false;
          _validating = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      final cancelled =
          error is UpdateException && error.failure == UpdateFailure.cancelled;
      setState(() {
        _cancelled = cancelled;
        _downloading = false;
        _validating = false;
      });
      if (!cancelled) _showFailure(error);
    }
  }

  void _showFailure(Object error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = error is UpdateException
        ? switch (error.failure) {
            UpdateFailure.network => l10n.updateErrorNetwork,
            UpdateFailure.invalidRelease => l10n.updateErrorInvalidRelease,
            UpdateFailure.unsupportedPlatform => l10n.updateErrorUnsupported,
            UpdateFailure.integrity => l10n.updateErrorIntegrity,
            UpdateFailure.fileAccess => l10n.updateErrorFileAccess,
            UpdateFailure.cancelled => l10n.updateCancelled,
          }
        : l10n.updateErrorUnexpected;
    showErrorNotice(context, error, message: message);
  }

  Future<void> _openFolder() async {
    final path = _directory;
    if (path == null) return;
    try {
      final result = await Process.run(
        Platform.isWindows ? 'explorer.exe' : 'xdg-open',
        [path],
      );
      if (result.exitCode != 0) {
        throw FileSystemException('Could not open download folder', path);
      }
    } catch (error) {
      _showFailure(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assets = _release == null
        ? const <UpdateAsset>[]
        : _service.packages(_release!);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_release == null)
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
                iconSize: 16,
              ),
              onPressed: _checking || _downloading ? null : _check,
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(
                _checking ? l10n.updateChecking : l10n.checkForUpdates,
              ),
            ),
          ),
        if (_release != null) ...[
          if (_release!.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _release!.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          if (assets.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.updateNoPackage),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                _release!.pageUrl,
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.updateReleasePage),
            ),
          ] else ...[
            const SizedBox(height: 8),
            for (final asset in assets)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _downloading ? null : () => _download(asset),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    l10n.updateDownloadAsset(_assetLabel(asset.name)),
                  ),
                ),
              ),
          ],
        ],
        if (_downloading) ...[
          const SizedBox(height: 8),
          Text(
            _validating ? l10n.updateValidating : l10n.updateDownloading,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          LinearProgressIndicator(
            value: !_validating && _total > 0
                ? (_received / _total).clamp(0.0, 1.0)
                : null,
          ),
          if (_total > 0)
            Text(
              '${(_received / _total * 100).clamp(0, 100).toStringAsFixed(1)}%',
            ),
          Text(_directory ?? '', style: Theme.of(context).textTheme.bodySmall),
          TextButton(
            onPressed: () {
              _cancelRequested = true;
              _service.cancelDownload();
            },
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
        if (_cancelled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l10n.updateCancelled),
          ),
        if (_filePath case final path?) ...[
          const SizedBox(height: 8),
          Text(l10n.updateDownloadComplete),
          SelectableText(path),
          TextButton.icon(
            onPressed: _openFolder,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(l10n.updateOpenFolder),
          ),
        ],
      ],
    );
    if (_release == null) return content;
    return AlertDialog(
      title: Text(l10n.updateAvailable(_release!.version)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _downloading
                ? MaterialLocalizations.of(context).cancelButtonLabel
                : l10n.close,
          ),
        ),
      ],
    );
  }

  String _assetLabel(String name) {
    final match = RegExp(r'-(windows|linux)-(amd64|arm64)').firstMatch(name);
    if (match == null) return name;
    final suffix = name.substring(
      name.indexOf(match.group(0)!) + match.group(0)!.length,
    );
    return '${match.group(1)} ${match.group(2)} ${suffix.replaceFirst(RegExp(r'^[-.]'), '')}';
  }
}
