import 'package:flutter/material.dart';

// 全局等宽字体（如需引入自定义字体，可替换此常量并在 pubspec.yaml 注册）
const String kCodeFontFamily = 'monospace';

// 扩展 TextTheme 以提供统一 code 样式
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
