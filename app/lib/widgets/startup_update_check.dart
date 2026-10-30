import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/ui_settings_provider.dart';
import '../services/app_logger.dart';
import '../services/update_service.dart';
import 'update_panel.dart';

class StartupUpdateCheck extends ConsumerStatefulWidget {
  const StartupUpdateCheck({
    super.key,
    required this.child,
    this.updateService,
  });

  final Widget child;
  final UpdateService? updateService;

  @override
  ConsumerState<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _StartupUpdateCheckState extends ConsumerState<StartupUpdateCheck> {
  late final UpdateService _service = widget.updateService ?? UpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(uiSettingsProvider).autoCheckUpdates) {
        unawaited(_check());
      }
    });
  }

  Future<void> _check() async {
    try {
      final package = await PackageInfo.fromPlatform();
      if (!mounted || !ref.read(uiSettingsProvider).autoCheckUpdates) return;
      final release = await _service.check(package.version);
      if (!mounted ||
          release == null ||
          !ref.read(uiSettingsProvider).autoCheckUpdates) {
        return;
      }
      await showUpdateDialog(context, release);
    } catch (error) {
      if (mounted) {
        AppLogger.instance.warning(
          'Automatic update check failed',
          error: error,
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.updateService == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
