import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../platform/notifications.dart';
import 'pages/exams_page.dart';
import 'pages/import_export_page.dart';
import 'pages/settings_page.dart';
import 'pages/timetable_page.dart';
import 'theme.dart';

/// 主窗口：编辑课表、管理考试、导入导出、设置。
class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.state, required this.reminders});

  final AppState state;
  final ReminderService reminders;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'DeskTile 课表岛',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: themeModeOf(state.settings.theme),
          home: _Shell(reminders: reminders),
        ),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.reminders});

  final ReminderService reminders;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TimetablePage(),
      const ExamsPage(),
      const ImportExportPage(),
      SettingsPage(reminders: widget.reminders),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: Icon(Icons.grid_view_rounded, size: 26),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.calendar_view_week_outlined),
                selectedIcon: Icon(Icons.calendar_view_week),
                label: Text('课表'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: Text('考试'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.import_export_outlined),
                selectedIcon: Icon(Icons.import_export),
                label: Text('导入导出'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}
