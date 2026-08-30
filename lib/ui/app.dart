import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../platform/notifications.dart';
import 'pages/exams_page.dart';
import 'pages/import_export_page.dart';
import 'pages/more_page.dart';
import 'pages/settings_page.dart';
import 'pages/tasks_page.dart';
import 'pages/timetable_page.dart';
import 'pages/today_page.dart';
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
  static const _compactBreakpoint = 640.0;

  _MainSection _section = _MainSection.today;

  Widget _page(_MainSection section) => switch (section) {
    _MainSection.today => TodayPage(reminders: widget.reminders),
    _MainSection.timetable => const TimetablePage(),
    _MainSection.tasks => TasksPage(reminders: widget.reminders),
    _MainSection.exams => const ExamsPage(),
    _MainSection.importExport => const ImportExportPage(),
    _MainSection.settings => SettingsPage(reminders: widget.reminders),
    _MainSection.more => MorePage(reminders: widget.reminders),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        final sections = compact ? _compactSections : _wideSections;
        final displaySection = sections.contains(_section)
            ? _section
            : compact
            ? _MainSection.more
            : _MainSection.settings;
        final selectedIndex = sections.indexOf(displaySection);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: compact
                ? _page(displaySection)
                : Row(
                    children: [
                      NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (i) =>
                            setState(() => _section = sections[i]),
                        labelType: NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.only(top: 12, bottom: 4),
                          child: Icon(Icons.grid_view_rounded, size: 26),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.today_outlined),
                            selectedIcon: Icon(Icons.today),
                            label: Text('今天'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.calendar_view_week_outlined),
                            selectedIcon: Icon(Icons.calendar_view_week),
                            label: Text('课表'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.assignment_outlined),
                            selectedIcon: Icon(Icons.assignment),
                            label: Text('待办'),
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
                      Expanded(child: _page(displaySection)),
                    ],
                  ),
          ),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _section = sections[i]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.today_outlined),
                      selectedIcon: Icon(Icons.today),
                      label: '今天',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_view_week_outlined),
                      selectedIcon: Icon(Icons.calendar_view_week),
                      label: '课表',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      selectedIcon: Icon(Icons.assignment),
                      label: '待办',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.event_note_outlined),
                      selectedIcon: Icon(Icons.event_note),
                      label: '考试',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      selectedIcon: Icon(Icons.more),
                      label: '更多',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

enum _MainSection {
  today,
  timetable,
  tasks,
  exams,
  importExport,
  settings,
  more,
}

const _wideSections = [
  _MainSection.today,
  _MainSection.timetable,
  _MainSection.tasks,
  _MainSection.exams,
  _MainSection.importExport,
  _MainSection.settings,
];

const _compactSections = [
  _MainSection.today,
  _MainSection.timetable,
  _MainSection.tasks,
  _MainSection.exams,
  _MainSection.more,
];
