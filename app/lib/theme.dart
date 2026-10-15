import 'package:flutter/material.dart';

const String kCodeFontFamily = 'monospace';

extension CodeTextTheme on TextTheme {
  TextStyle get code => bodyMedium!.copyWith(fontFamily: kCodeFontFamily);
}

final availableThemeColors = [
  Colors.blue,
  Colors.red,
  Colors.green,
  Colors.purple,
  Colors.orange,
  Colors.cyan,
];

ThemeData getLightTheme(Color seedColor) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei',
  );
}

ThemeData getDarkTheme(Color seedColor) {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei',
  );
}
