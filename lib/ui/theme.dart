import 'package:flutter/material.dart';

import '../core/models/settings.dart';

const _seed = Color(0xFF3B6EA8);

ThemeMode themeModeOf(ThemePref pref) => switch (pref) {
      ThemePref.light => ThemeMode.light,
      ThemePref.dark => ThemeMode.dark,
      ThemePref.system => ThemeMode.system,
    };

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    fontFamily: 'Microsoft YaHei',
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}

/// 课程块配色：柔和、彼此区分度够，深浅色模式下都能读。
const _courseColors = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFF4CAF93),
  Color(0xFFE8834A),
  Color(0xFF9A7BD8),
  Color(0xFFD9646E),
  Color(0xFF4AA3C7),
  Color(0xFF8DA84C),
  Color(0xFFCB8A3E),
  Color(0xFF6E7FD8),
  Color(0xFFC66A9C),
];

/// 按课程的 colorSeed 取一个稳定的颜色。
Color courseColor(int seed, Brightness brightness) {
  final base = _courseColors[seed.abs() % _courseColors.length];
  return brightness == Brightness.dark
      ? Color.alphaBlend(Colors.black.withValues(alpha: 0.18), base)
      : base;
}

String monthDayText(DateTime d) => '${d.month}月${d.day}日';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
