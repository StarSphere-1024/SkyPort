import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/widgets/left_panel.dart';
import 'package:myapp/widgets/right_panel.dart';
import 'package:myapp/widgets/status_bar.dart';

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
      title: 'Flutter Serial Port Debugging Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
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
        title: const Text('Serial Port Debugging Assistant'),
      ),
      body: Row(
        children: [
          const SizedBox(
            width: 350,
            child: LeftPanel(),
          ),
          const VerticalDivider(width: 1),
          const Expanded(
            child: RightPanel(),
          ),
        ],
      ),
      bottomNavigationBar: const StatusBar(),
    );
  }
}
