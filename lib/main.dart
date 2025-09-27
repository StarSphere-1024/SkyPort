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
      title: 'SkyPort',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyPort'),
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
