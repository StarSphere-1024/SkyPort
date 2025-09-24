import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sky_port/widgets/left_panel.dart';
import 'package:sky_port/widgets/right_panel.dart';
import 'package:sky_port/widgets/status_bar.dart';

void main() {
  runApp(
    const ProviderScope(
      child: SerialDebuggerApp(),
    ),
  );
}

class SerialDebuggerApp extends StatelessWidget {
  const SerialDebuggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkyPort',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
