import 'package:flutter/material.dart';

const String kCodeFontFamily = 'monospace';

extension CodeTextTheme on TextTheme {
  TextStyle get code => bodyMedium!.copyWith(fontFamily: kCodeFontFamily);
}

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  useMaterial3: true,
  fontFamily: 'Microsoft YaHei',
);

final darkTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  fontFamily: 'Microsoft YaHei',
);
