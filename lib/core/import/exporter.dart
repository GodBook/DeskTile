import '../models/timetable.dart';
import '../week_math.dart';
import '../weeks_parser.dart';

/// 导出 CSES v2 YAML 的结果：文本 + 无法精确表达的内容说明。
class CsesExport {
  CsesExport({required this.yaml, required this.warnings});

  final String yaml;
  final List<String> warnings;
}

/// 把课表导出成 CSES v2 YAML（可被 ClassIsland 等软件读取）。
///
/// CSES 用「工作日循环」定位课程，只能表达每周相同或单双周两种节奏，
/// 而且 schema 要求 `work_count >= 2`、`rest_count >= 2`。所以：
///   - 周一~周五有课        -> 工作 5 休息 2
///   - 周六也有课            -> 工作 6 休息 1（为满足 rest_count>=2 会写成两周循环）
///   - 周日有课              -> 无法表达，直接报错
///   - 周次既不是每周也不是单/双周的时段 -> 跳过并在 warnings 里列出
CsesExport exportCses(Timetable timetable) {
  final warnings = <String>[];
  if (timetable.sessions.isEmpty) {
    throw const FormatException('课表里没有课，没什么可导出的');
  }
  if (timetable.scheduleChanges.isNotEmpty) {
    warnings.add('临时调课、停课和补课无法用 CSES 表达，未写入导出文件；JSON 备份会完整保留');
  }
  if (timetable.academicCalendarEvents.isNotEmpty) {
    warnings.add('学期校历和批量停课无法用 CSES 表达，未写入导出文件；JSON 备份会完整保留');
  }

  final all = allWeeks(timetable.totalWeeks);
  final odd = oddWeeks(timetable.totalWeeks);
  final even = evenWeeks(timetable.totalWeeks);

  // 归类每个时段的周次节奏。
  final kept =
      <({int day, String name, int section, String? room, String rhythm})>[];
  for (final s in timetable.sessions) {
    final course = timetable.courseById(s.courseId);
    if (course == null) continue;
    final String rhythm;
    if (setEquals(s.weeks, all)) {
      rhythm = 'all';
    } else if (setEquals(s.weeks, odd)) {
      rhythm = 'odd';
    } else if (setEquals(s.weeks, even)) {
      rhythm = 'even';
    } else {
      warnings.add(
        '「${course.name}」的周次是 '
        '${formatWeeks(s.weeks, totalWeeks: timetable.totalWeeks)}，'
        'CSES 只能表达每周/单周/双周，该时段已跳过',
      );
      continue;
    }
    if (s.day == 7) {
      throw const FormatException(
        '课表里有周日的课，CSES 的工作日循环无法表达（'
        'rest_count 至少为 2），无法导出',
      );
    }
    for (var sec = s.startSection; sec <= s.endSection; sec++) {
      kept.add((
        day: s.day,
        name: course.name,
        section: sec,
        room: s.room,
        rhythm: rhythm,
      ));
    }
  }
  if (kept.isEmpty) throw const FormatException('没有可以用 CSES 表达的时段');

  final maxDay = kept.map((e) => e.day).reduce((a, b) => a > b ? a : b);
  final workPerWeek = maxDay <= 5 ? 5 : 6;
  final restPerWeek = 7 - workPerWeek;
  final needsTwoWeeks = kept.any((e) => e.rhythm != 'all') || restPerWeek < 2;

  final weeksInCycle = needsTwoWeeks ? 2 : 1;
  final spans = <String>[];
  for (var i = 0; i < weeksInCycle; i++) {
    spans.add('    - activity: work\n      count: $workPerWeek');
    spans.add('    - activity: rest\n      count: $restPerWeek');
  }

  // 每个 (循环周, 星期) 一张日课表。
  final buckets =
      <(int, int), List<({String name, int section, String? room})>>{};
  for (final e in kept) {
    final targetCycleWeeks = switch (e.rhythm) {
      'odd' => const [1],
      'even' => const [2],
      _ => weeksInCycle == 2 ? const [1, 2] : const [1],
    };
    for (final cw in targetCycleWeeks) {
      buckets.putIfAbsent((cw, e.day), () => []).add((
        name: e.name,
        section: e.section,
        room: e.room,
      ));
    }
  }

  // subjects：教室取该课程出现过的第一个。
  final subjectRoom = <String, String?>{};
  final subjectTeacher = <String, String?>{};
  for (final course in timetable.courses) {
    subjectTeacher[course.name] = course.teacher;
  }
  for (final e in kept) {
    subjectRoom.putIfAbsent(e.name, () => e.room);
  }

  final sb = StringBuffer()
    ..writeln('version: 2')
    ..writeln('configuration:')
    ..writeln('  name: ${_yaml(timetable.name)}')
    ..writeln(
      '  description: ${_yaml('由 DeskTile 课表岛导出，'
      '学期第一周周一 ${_dateText(timetable.termStart)}，共 ${timetable.totalWeeks} 周')}',
    )
    ..writeln('  cycle:')
    ..writeln('    work_count: ${workPerWeek * weeksInCycle}')
    ..writeln('    rest_count: ${restPerWeek * weeksInCycle}')
    ..writeln('    spans:')
    ..writeln(spans.join('\n'))
    ..writeln('subjects:');

  final subjectNames =
      buckets.values.expand((list) => list.map((c) => c.name)).toSet().toList()
        ..sort();
  for (final name in subjectNames) {
    sb.writeln('  - name: ${_yaml(name)}');
    final teacher = subjectTeacher[name];
    if (teacher != null) sb.writeln('    teacher: ${_yaml(teacher)}');
    final room = subjectRoom[name];
    if (room != null) sb.writeln('    location: ${_yaml(room)}');
  }

  sb.writeln('schedules:');
  final keys = buckets.keys.toList()
    ..sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
  for (final key in keys) {
    final (cycleWeek, day) = key;
    final classes = buckets[key]!
      ..sort((a, b) => a.section.compareTo(b.section));
    final label = weeksInCycle == 2
        ? '${weekDayName(day)}-${cycleWeek == 1 ? '单周' : '双周'}'
        : weekDayName(day);
    final enableDay = (cycleWeek - 1) * workPerWeek + day;
    sb
      ..writeln('  - name: ${_yaml(label)}')
      ..writeln('    enable_day:')
      ..writeln('      - $enableDay')
      ..writeln('    classes:');
    for (final c in classes) {
      final slot = timetable.slotAt(c.section);
      if (slot == null) {
        warnings.add('第 ${c.section} 节没有时间定义，「${c.name}」的这一节已跳过');
        continue;
      }
      sb
        ..writeln('      - subject: ${_yaml(c.name)}')
        ..writeln('        start_time: "${slot.startText}:00"')
        ..writeln('        end_time: "${slot.endText}:00"');
    }
  }

  return CsesExport(yaml: sb.toString(), warnings: warnings);
}

String _yaml(String value) =>
    '"${value.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"';

String _dateText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
