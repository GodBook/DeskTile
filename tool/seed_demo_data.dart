// 用真实的导入代码把 docs/示例课表.csv 灌进应用的数据文件，方便验证界面。
//
// 用法（在项目根目录）：
//   dart run tool/seed_demo_data.dart
//   dart run tool/seed_demo_data.dart --weeks-back 1     # 让「本周」落在第 2 周，验证单双周
//   dart run tool/seed_demo_data.dart --reminder-test    # 造一节 3 分钟后开始的课，验证提醒真的会弹
//   dart run tool/seed_demo_data.dart --export-cses out.yaml  # 导出 CSES，便于用官方 schema 校验
//   dart run tool/seed_demo_data.dart --dir "C:\path"
//
// 默认写到 %APPDATA%\com.desktile\desktile\desktile_data.json，
// 也就是 path_provider 在 Windows 上给出的 application support 目录。

import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/import/course_info_dto.dart';
import 'package:desktile/core/import/csv_importer.dart';
import 'package:desktile/core/import/exporter.dart';
import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/models/time_slot.dart';
import 'package:desktile/core/models/timetable.dart';
import 'package:desktile/core/week_math.dart';
import 'package:desktile/data/app_data.dart';

void main(List<String> args) {
  final dirIndex = args.indexOf('--dir');
  final dirPath = dirIndex >= 0 && dirIndex + 1 < args.length
      ? args[dirIndex + 1]
      : '${Platform.environment['APPDATA']}\\com.desktile\\desktile';

  final backIndex = args.indexOf('--weeks-back');
  final weeksBack = backIndex >= 0 && backIndex + 1 < args.length
      ? int.parse(args[backIndex + 1])
      : 0;

  final data = args.contains('--reminder-test')
      ? _reminderTestData()
      : _demoData(weeksBack);

  final exportIndex = args.indexOf('--export-cses');
  if (exportIndex >= 0 && exportIndex + 1 < args.length) {
    final result = exportCses(data.activeTimetable!);
    File(args[exportIndex + 1]).writeAsBytesSync(utf8.encode(result.yaml));
    stdout.writeln('已导出 CSES 到 ${args[exportIndex + 1]}');
    for (final w in result.warnings) {
      stdout.writeln('导出警告: $w');
    }
    return;
  }

  final dir = Directory(dirPath)..createSync(recursive: true);
  final file = File('${dir.path}\\desktile_data.json');
  file.writeAsBytesSync(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data.toJson())));

  final t = data.activeTimetable!;
  stdout.writeln('已写入 ${file.path}');
  stdout.writeln('课表「${t.name}」：课程 ${t.courses.length} 门，时段 ${t.sessions.length} 个，'
      '学期第一周周一 ${t.termStart.toIso8601String().substring(0, 10)}，'
      '本周是第 ${clampedWeek(t.termStart, DateTime.now(), t.totalWeeks)} 周');
}

AppData _demoData(int weeksBack) {
  final csv = utf8.decode(File('docs/示例课表.csv').readAsBytesSync());
  const totalWeeks = 16;
  final imported = importCsv(csv, totalWeeks: totalWeeks);

  final warnings = <String>[];
  // 学期第一周的周一默认设成本周周一，这样打开就能看到「本周」有课。
  final termStart =
      mondayOf(DateTime.now()).subtract(Duration(days: 7 * weeksBack));
  final timetable = buildTimetable(
    id: 't1',
    name: '2026 秋季学期',
    termStart: termStart,
    imported: imported,
    warnings: warnings,
    totalWeeks: totalWeeks,
  );
  for (final w in [...imported.warnings, ...warnings]) {
    stdout.writeln('警告: $w');
  }

  final today = DateTime.now();
  return AppData(
    timetables: [timetable],
    activeTimetableId: 't1',
    exams: [
      Exam(
        id: 'e1',
        name: '高等数学A 期末',
        startAt: DateTime(today.year, today.month, today.day, 9)
            .add(const Duration(days: 12)),
        endAt: DateTime(today.year, today.month, today.day, 11)
            .add(const Duration(days: 12)),
        room: '教三-305',
        seat: '18',
      ),
      Exam(
        id: 'e2',
        name: '线性代数 期末',
        startAt: DateTime(today.year, today.month, today.day, 14)
            .add(const Duration(days: 2)),
        room: '教三-208',
        seat: '7',
      ),
    ],
    settings: const AppSettings(),
  );
}

/// 造一节「4 分钟后开始」的课，配上「提前 3 分钟提醒」，
/// 这样应用一启动就会把提醒排在大约 1 分钟后，用来验证 Windows 通知真的会弹。
AppData _reminderTestData() {
  final now = DateTime.now();
  final startMinutes = now.hour * 60 + now.minute + 4;
  final termStart = mondayOf(now);
  final timetable = Timetable(
    id: 't1',
    name: '提醒验证',
    termStart: termStart,
    totalWeeks: 16,
    timeSlots: [
      TimeSlot(
        index: 1,
        startMinutes: startMinutes,
        endMinutes: startMinutes + 45,
      ),
    ],
    courses: const [Course(id: 'c1', name: '高等数学A', teacher: '张伟')],
    sessions: [
      CourseSession(
        id: 's1',
        courseId: 'c1',
        day: now.weekday,
        startSection: 1,
        endSection: 1,
        weeks: allWeeks(16),
        room: '教三-305',
      ),
    ],
  );
  stdout.writeln('提醒验证：课程 ${formatMinutes(startMinutes)} 开始，'
      '提醒应在约 ${formatMinutes(startMinutes - 3)} 弹出');
  return AppData(
    timetables: [timetable],
    activeTimetableId: 't1',
    exams: const [],
    settings: const AppSettings(
      leadMinutes: 3,
      earlyClassCutoffMinutes: 24 * 60,
    ),
  );
}
