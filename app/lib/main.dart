import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'host_core.dart';
import 'models/ui_state.dart';
import 'providers/common_providers.dart';
import 'providers/ui_controller.dart';
import 'providers/theme_provider.dart';
import 'theme.dart';
import 'widgets/application_settings.dart';
import 'widgets/connection_rail.dart';
import 'widgets/left_panel.dart';
import 'widgets/right_panel.dart';
import 'widgets/status_bar.dart';
import 'widgets/desktop_window_frame.dart';
import 'services/app_logger.dart';
import 'l10n/app_localizations.dart';
import 'utils/error_messages.dart';
import 'widgets/shared/error_notice.dart';

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
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      throw HostStartupException(HostFailure.preferencesUnavailable, error);
    }
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
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => DesktopWindowFrame(child: child!),
        home: StartupFailurePage(details: startupFailure!),
      );
    }
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final hasManualColor = ref.watch(hasManualThemeColorProvider);
    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final systemAccent = ref.watch(systemAccentColorProvider);
    Color seedFor(Brightness brightness) => resolveThemeColor(
      dynamicEnabled: dynamicEnabled,
      manualSeed: hasManualColor ? themeColor : null,
      systemAccent: systemAccent,
      brightness: brightness,
    ).seed;
    return _DynamicAccentColorMonitor(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: getLightTheme(seedFor(Brightness.light)),
        darkTheme: getDarkTheme(seedFor(Brightness.dark)),
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => DesktopWindowFrame(child: child!),
        home: const HomePage(),
      ),
    );
  }
}

class _DynamicAccentColorMonitor extends ConsumerStatefulWidget {
  const _DynamicAccentColorMonitor({required this.child});
  final Widget child;

  @override
  ConsumerState<_DynamicAccentColorMonitor> createState() =>
      _DynamicAccentColorMonitorState();
}

class _DynamicAccentColorMonitorState
    extends ConsumerState<_DynamicAccentColorMonitor> {
  Timer? _timer;
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(dynamicColorEnabledProvider);
    final supported =
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;
    if (enabled && supported) {
      // ponytail: poll plugin reads; use native events if 10s polling proves costly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _timer != null) return;
        _refreshAccent();
        _timer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _refreshAccent(),
        );
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    return widget.child;
  }

  Future<void> _refreshAccent() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final color = await DynamicColorPlugin.getAccentColor();
      if (mounted) {
        ref.read(systemAccentColorProvider.notifier).setColor(color);
      }
    } on PlatformException {
      if (mounted) ref.read(systemAccentColorProvider.notifier).setColor(null);
    } on MissingPluginException {
      if (mounted) ref.read(systemAccentColorProvider.notifier).setColor(null);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
              SelectableText(localizedError(l10n, details)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => showErrorDetails(context, details),
                child: Text(l10n.diagnosticDetails),
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

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  static const _panelOpenKey = 'ui_configuration_panel_open';
  late TextEditingController _bufferController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final AnimationController _panelAnimation;
  late bool _panelOpen;
  bool _settingsSelected = false;

  @override
  void initState() {
    super.initState();
    _panelOpen =
        ref.read(sharedPreferencesProvider).getBool(_panelOpenKey) ?? true;
    _panelAnimation = AnimationController(
      vsync: this,
      value: _panelOpen ? 1 : 0,
    );
    final megabytes =
        ref.read(uiControllerProvider).logCapacityBytes ~/ (1024 * 1024);
    _bufferController = TextEditingController(text: '$megabytes');
  }

  @override
  void dispose() {
    _bufferController.dispose();
    _panelAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<UiErrorNotice>>(
      uiControllerProvider.select((value) => value.errorNotices),
      (previous, next) {
        for (final notice in next) {
          if (notice.reconnecting &&
              ref.read(uiControllerProvider).connection !=
                  UiConnection.reconnecting) {
            continue;
          }
          showErrorNotice(
            context,
            notice.error,
            message: notice.reconnecting
                ? AppLocalizations.of(context).disconnectedReconnecting
                : null,
          );
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _setPanelOpen(false),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 800;
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    ConnectionRail(
                      panelOpen: _panelOpen,
                      settingsSelected: _settingsSelected,
                      onSerial: () => _openPage(false),
                      onSettings: () => _openPage(true),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final panelWidth = constraints.maxWidth
                                    .clamp(0, 310)
                                    .toDouble();
                                return AnimatedBuilder(
                                  animation: _panelAnimation,
                                  child: _configurationPanel(context),
                                  builder: (context, panel) {
                                    final visibleWidth =
                                        panelWidth * _panelAnimation.value;
                                    return Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Positioned.fill(
                                          child: Padding(
                                            padding: EdgeInsetsDirectional.only(
                                              start: compact ? 0 : visibleWidth,
                                            ),
                                            child: ExcludeFocus(
                                              excluding: compact && _panelOpen,
                                              child: IgnorePointer(
                                                ignoring: compact && _panelOpen,
                                                child: const RightPanel(),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (compact && _panelOpen)
                                          Positioned.fill(
                                            child: ModalBarrier(
                                              dismissible: false,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .scrim
                                                  .withValues(alpha: 0.32),
                                            ),
                                          ),
                                        PositionedDirectional(
                                          start: visibleWidth - panelWidth,
                                          top: 0,
                                          bottom: 0,
                                          width: panelWidth,
                                          child: ExcludeFocus(
                                            excluding: !_panelOpen,
                                            child: ExcludeSemantics(
                                              excluding: !_panelOpen,
                                              child: IgnorePointer(
                                                ignoring: !_panelOpen,
                                                child: panel,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: const StatusBar(),
            );
          },
        ),
      ),
    );
  }

  void _setPanelOpen(bool open) {
    if (_panelOpen == open) return;
    setState(() => _panelOpen = open);
    ref.read(sharedPreferencesProvider).setBool(_panelOpenKey, open);
    _panelAnimation.animateTo(
      open ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
    );
  }

  void _openPage(bool settings) {
    final open = !_panelOpen || _settingsSelected != settings;
    setState(() => _settingsSelected = settings);
    _setPanelOpen(open);
  }

  Widget _configurationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          border: fieldBorder,
        ),
        dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
          inputDecorationTheme: const InputDecorationThemeData(
            border: fieldBorder,
          ),
          menuStyle: const MenuStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: IndexedStack(
            index: _settingsSelected ? 1 : 0,
            children: [
              const LeftPanel(),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ApplicationSettings(
                  controller: _bufferController,
                  formKey: _formKey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
