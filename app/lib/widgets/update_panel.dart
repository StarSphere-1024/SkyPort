import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../providers/ui_settings_provider.dart';
import '../services/update_service.dart';
import 'shared/error_notice.dart';

Future<void> showUpdateDialog(BuildContext context, AppRelease release) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdatePanel._details(release: release),
    );

class UpdatePanel extends ConsumerStatefulWidget {
  const UpdatePanel({super.key, this.updateService}) : initialRelease = null;

  const UpdatePanel._details({required AppRelease release})
    : initialRelease = release,
      updateService = null;

  final UpdateService? updateService;
  final AppRelease? initialRelease;

  @override
  ConsumerState<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends ConsumerState<UpdatePanel> {
  late final UpdateService _service = widget.updateService ?? UpdateService();
  bool _checking = false;
  bool _saving = false;
  bool _opening = false;

  @override
  void dispose() {
    if (widget.updateService == null) _service.dispose();
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
        await showUpdateDialog(context, release);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _checking = false);
      final l10n = AppLocalizations.of(context);
      final message = error is UpdateException
          ? switch (error.failure) {
              UpdateFailure.network => l10n.updateErrorNetwork,
              UpdateFailure.invalidRelease => l10n.updateErrorInvalidRelease,
              UpdateFailure.cancelled => l10n.updateErrorUnexpected,
            }
          : l10n.updateErrorUnexpected;
      showErrorNotice(context, error, message: message);
    }
  }

  Future<void> _ignoreVersion(bool value) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(uiSettingsProvider.notifier)
          .setIgnoredUpdateVersion(value ? widget.initialRelease!.version : '');
    } catch (error) {
      if (mounted) {
        showErrorNotice(
          context,
          error,
          message: AppLocalizations.of(context).updateErrorSavePreference,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openRelease() async {
    setState(() => _opening = true);
    try {
      final opened = await launchUrl(
        widget.initialRelease!.pageUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Could not open release page');
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        showErrorNotice(
          context,
          error,
          message: AppLocalizations.of(context).updateErrorOpenPage,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final release = widget.initialRelease;
    if (release == null) {
      return Center(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const StadiumBorder(),
            iconSize: 16,
          ),
          onPressed: _checking ? null : _check,
          icon: _checking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
          label: Text(_checking ? l10n.updateChecking : l10n.checkForUpdates),
        ),
      );
    }
    final busy = _saving || _opening;
    final ignored = ref.watch(
      uiSettingsProvider.select((settings) => settings.ignoredUpdateVersion),
    );
    return AlertDialog(
      title: Text(l10n.updateAvailable(release.version)),
      content: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(l10n.updateIgnoreVersion),
        value: ignored == release.version,
        onChanged: busy ? null : (value) => _ignoreVersion(value!),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.updateLater),
        ),
        FilledButton(
          onPressed: busy ? null : _openRelease,
          child: Text(l10n.updateReleasePage),
        ),
      ],
    );
  }
}
