import 'package:flutter/material.dart';

import '../../platform/notifications.dart';
import 'academic_calendar_page.dart';
import 'import_export_page.dart';
import 'settings_page.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.reminders});

  final ReminderService reminders;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('更多', style: Theme.of(context).textTheme.titleMedium),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.date_range_outlined),
        title: const Text('学期校历'),
        subtitle: const Text('管理假期、考试周和批量停课'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            _open(context, title: '学期校历', child: const AcademicCalendarPage()),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.import_export_outlined),
        title: const Text('导入导出'),
        subtitle: const Text('导入课表、导出备份和 CSES 文件'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            _open(context, title: '导入导出', child: const ImportExportPage()),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('设置'),
        subtitle: const Text('学期、提醒、挂件、后台与应用更新'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(
          context,
          title: '设置',
          child: SettingsPage(reminders: reminders),
        ),
      ),
      const Divider(height: 1),
    ],
  );
}

void _open(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: child),
      ),
    ),
  );
}
