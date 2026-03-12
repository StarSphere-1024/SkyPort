import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/common_providers.dart';
import 'providers/serial/error_provider.dart';
import 'providers/serial/ui_settings_provider.dart';
import 'providers/serial/serial_config_provider.dart';
import 'providers/serial/data_log_provider.dart';
import 'models/app_error.dart';
import 'providers/theme_provider.dart';
import 'theme.dart';
import 'widgets/settings_popup.dart';
import 'widgets/left_panel.dart';
import 'widgets/right_panel.dart';
import 'widgets/status_bar.dart';
import 'services/log_export_service.dart';
import 'l10n/app_localizations.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // For desktop platforms, initialize window manager.
  // For mobile, you might want to use packages like usb_serial.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SerialDebuggerApp(),
    ),
  );
}

class SerialDebuggerApp extends ConsumerWidget {
  const SerialDebuggerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final initialSize = ref.read(uiSettingsProvider).logBufferSize;
    _bufferController = TextEditingController(text: '$initialSize');
  }

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppError?>(errorProvider, (prev, next) {
      final error = next;
      if (error != null && error.type != AppErrorType.none) {
        final loc = AppLocalizations.of(context);
        final message = ref.read(errorProvider.notifier).getErrorMessage(loc);

        if (message.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: SelectableText(
                message,
              ),
            ),
          );
          ref.read(errorProvider.notifier).clear();
        }
      }
    });
    ref.listen<int>(uiSettingsProvider.select((s) => s.logBufferSize),
        (prev, next) {
      if (_bufferController.text != '$next') {
        _bufferController.text = '$next';
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
        actions: [
          // Export logs button
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: AppLocalizations.of(context).exportLogs,
            onPressed: () async {
              if (!context.mounted) return;

              // Get current state - export matches current UI display (WYSIWYG)
              final logState = ref.read(dataLogProvider);
              final settings = ref.read(uiSettingsProvider);
              final serialConfig = ref.read(serialConfigProvider);

              // Export logs with all UI settings for WYSIWYG output
              await LogExportService.exportLogs(
                context: context,
                chunks: logState.chunks,
                showSent: settings.showSent,
                hexDisplay: settings.hexDisplay,
                showTimestamp: settings.showTimestamp,
                enableAnsi: settings.enableAnsi,
                defaultPath: settings.logExportPath,
                portName: serialConfig?.portName ?? '',
              );
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

                final RenderBox button = context.findRenderObject() as RenderBox;
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
            Expanded(
              child: RightPanel(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const StatusBar(),
    );
  }
}
