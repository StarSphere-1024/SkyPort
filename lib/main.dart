import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sky_port/providers/serial_provider.dart';
import 'package:sky_port/theme.dart';
import 'package:sky_port/widgets/left_panel.dart';
import 'package:sky_port/widgets/right_panel.dart';
import 'package:sky_port/widgets/status_bar.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // For desktop platforms, initialize window manager.
  // For mobile, you might want to use packages like usb_serial.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(800, 600),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = ProviderContainer();
  await container.read(availablePortsProvider.future);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SerialDebuggerApp(),
    ),
  );
}

class SerialDebuggerApp extends StatelessWidget {
  const SerialDebuggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 错误监听：出现错误时弹出 SnackBar，不覆盖状态栏文本
    ref.listen<String?>(errorProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        // 显示后清空，避免重复
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next)));
        ref.read(errorProvider.notifier).clear();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
      ),
      body: const SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 350,
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
