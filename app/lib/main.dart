import 'dart:ui';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyport/src/rust/api.dart' as rust;
import 'host_core.dart';
import 'providers/common_providers.dart';
import 'providers/ui_settings_provider.dart';
import 'providers/ui_controller.dart';
import 'providers/theme_provider.dart';
import 'theme.dart';
import 'widgets/settings_popup.dart';
import 'widgets/left_panel.dart';
import 'widgets/right_panel.dart';
import 'widgets/status_bar.dart';
import 'services/app_logger.dart';
import 'services/log_export_service.dart';
import 'l10n/app_localizations.dart';
import 'utils/constants.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.instance.error(
      'Unhandled Flutter framework error',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.instance.error(
      'Unhandled async error',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };

  if (args.contains('--kernel-smoke')) {
    try {
      await runKernelSmoke(args);
      exit(0);
    } catch (error, stackTrace) {
      stderr.writeln('$error\n$stackTrace');
      exit(1);
    }
  }

  SharedPreferences? prefs;
  CoreBootstrap? bootstrap;
  Object? startupFailure;
  try {
    await AppLogger.instance.initialize();
    prefs = await SharedPreferences.getInstance();
    bootstrap = await createCoreFromHost(prefs);
  } catch (error, stackTrace) {
    startupFailure = error;
    AppLogger.instance.error(
      'Core startup failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
  await installHostCloseHandler(bootstrap);
  final container = ProviderContainer(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      if (bootstrap != null) coreBootstrapProvider.overrideWithValue(bootstrap),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: SerialDebuggerApp(startupFailure: startupFailure),
    ),
  );
}

class SerialDebuggerApp extends ConsumerWidget {
  const SerialDebuggerApp({super.key, this.startupFailure});
  final Object? startupFailure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (startupFailure != null) {
      return MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupFailurePage(details: startupFailure!),
      );
    }
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: getLightTheme(themeColor),
      darkTheme: getDarkTheme(themeColor),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}

class StartupFailurePage extends StatelessWidget {
  const StartupFailurePage({required this.details, super.key});
  final Object details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.startupFailed,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              SelectableText(
                details is CoreHostException
                    ? _errorMessage(l10n, (details as CoreHostException).error)
                    : '$details',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static final GlobalKey _settingsKey = GlobalKey();
  late TextEditingController _bufferController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final megabytes =
        ref.read(uiControllerProvider).logCapacityBytes ~/ (1024 * 1024);
    _bufferController = TextEditingController(text: '$megabytes');
  }

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<rust.CoreError?>(
      uiControllerProvider.select((value) => value.error),
      (previous, next) {
        if (next != null && previous != next) {
          final message = _errorMessage(AppLocalizations.of(context), next);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: SelectableText(message)));
        }
      },
    );
    ref.listen<int>(
      uiControllerProvider.select((value) => value.logCapacityBytes),
      (previous, next) {
        final megabytes = next ~/ (1024 * 1024);
        if (_bufferController.text != '$megabytes') {
          _bufferController.text = '$megabytes';
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
        actions: [
          // Export logs button
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: AppLocalizations.of(context).exportLogs,
            onPressed: () async {
              final settings = ref.read(uiSettingsProvider);
              final state = ref.read(uiControllerProvider);
              await LogExportService.exportLogs(
                context: context,
                defaultPath: settings.logExportPath,
                portName: state.portName,
                export: (path) => ref
                    .read(uiControllerProvider.notifier)
                    .exportLog(
                      path,
                      rust.ExportOptions(
                        showSent: settings.showSent,
                        hex: settings.hexDisplay,
                        timestamps: settings.showTimestamp,
                        stripAnsi: settings.enableAnsi,
                      ),
                    ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: AppLocalizations.of(context).importFile,
            onPressed: () async {
              final file = await openFile();
              final path = file?.path;
              if (path != null && context.mounted) {
                await ref.read(uiControllerProvider.notifier).importFile(path);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              key: _settingsKey,
              icon: const Icon(Icons.settings),
              onPressed: () {
                final context = _settingsKey.currentContext;
                if (context == null) return;

                final RenderBox button =
                    context.findRenderObject() as RenderBox;
                final Offset offset = button.localToGlobal(Offset.zero);
                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    offset.dx,
                    offset.dy + button.size.height,
                    offset.dx + button.size.width,
                    offset.dy + button.size.height,
                  ),
                  items: [
                    PopupMenuItem(
                      enabled: false,
                      child: SizedBox(
                        width: SkyPortConstants.settingsPopupWidth.toDouble(),
                        child: SettingsPopup(
                          controller: _bufferController,
                          formKey: _formKey,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: SkyPortConstants.leftPanelWidth.toDouble(),
              child: LeftPanel(),
            ),
            VerticalDivider(width: 1),
            Expanded(child: RightPanel()),
          ],
        ),
      ),
      bottomNavigationBar: const StatusBar(),
    );
  }
}

String _errorMessage(AppLocalizations l10n, rust.CoreError error) {
  if (error.kind == rust.ErrorKind.writeFailed || error.bytesWritten > 0) {
    return l10n.writeFailure(error.bytesWritten, error.message);
  }
  final label = switch (error.kind) {
    rust.ErrorKind.invalidArgument => l10n.errorInvalidArgument,
    rust.ErrorKind.portNotFound => l10n.errorPortNotFound,
    rust.ErrorKind.openFailed => l10n.errorOpenFailed,
    rust.ErrorKind.permissionDenied => l10n.errorPermissionDenied,
    rust.ErrorKind.unsupportedConfiguration =>
      l10n.errorUnsupportedConfiguration,
    rust.ErrorKind.readFailed => l10n.errorReadFailed,
    rust.ErrorKind.disconnected => l10n.errorDisconnected,
    rust.ErrorKind.timeout => l10n.errorTimeout,
    rust.ErrorKind.closed => l10n.errorClosed,
    rust.ErrorKind.queueOverflow => l10n.errorQueueOverflow,
    rust.ErrorKind.taskFailed => l10n.errorTaskFailed,
    rust.ErrorKind.internal => l10n.errorInternal,
    rust.ErrorKind.writeFailed => l10n.writeFailure(0, error.message),
  };
  return '$label: ${error.message}';
}
