import 'package:yaml/yaml.dart';

import '../models/time_slot.dart';
import '../week_math.dart';
import 'course_info_dto.dart';

/// 导入 CSES v2（Course Schedule Exchange Schema）YAML。
///
/// CSES 用「循环中的第几个工作日」（`enable_day`）而不是星期几来定位课程，
/// 所以要先按 `configuration.cycle.spans` 把工作日序号还原成日历上的星期几
/// 和所处的循环周。目前支持 1 周和 2 周循环（2 周循环映射为单/双周），
/// 更长的循环我们的模型表达不了，会明确报错而不是悄悄算错。
///
/// CSES 也没有「节次」概念，只有具体时刻，所以节次时间表是从文件里出现过的
/// 所有时间段推出来的。
ImportedSchedule importCses(String yamlContent, {int totalWeeks = 20}) {
  final warnings = <String>[];
  final doc = loadYaml(yamlContent);
  if (doc is! Map) throw const FormatException('CSES 文件不是一个 YAML 映射');

  final version = doc['version'];
  if (version != 2) {
    warnings.add('CSES 版本是 $version，本程序按 v2 解析，可能有出入');
  }

  final config = doc['configuration'];
  if (config is! Map) throw const FormatException('CSES 缺少 configuration');
  final cycle = config['cycle'];
  if (cycle is! Map) throw const FormatException('CSES 缺少 configuration.cycle');

  final layout = _resolveCycle(cycle);

  // subjects: 课程名 -> 教师/地点
  final subjectInfo = <String, ({String? teacher, String? location})>{};
  final subjects = doc['subjects'];
  if (subjects is List) {
    for (final s in subjects) {
      if (s is! Map) continue;
      final name = '${s['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      subjectInfo[name] = (
        teacher: _orNull(s['teacher']),
        location: _orNull(s['location']),
      );
    }
  }

  final schedules = doc['schedules'];
  if (schedules is! List || schedules.isEmpty) {
    throw const FormatException('CSES 里没有 schedules');
  }

  // 先扫一遍所有时间段，推出节次时间表。
  final slotKeys = <(int, int)>{};
  for (final sch in schedules) {
    if (sch is! Map) continue;
    for (final c in (sch['classes'] as List? ?? const [])) {
      if (c is! Map) continue;
      final start = _minutes(c['start_time']);
      final end = _minutes(c['end_time']);
      if (start == null || end == null) continue;
      slotKeys.add((start, end));
    }
  }
  final sortedSlots = slotKeys.toList()
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  final timeSlots = [
    for (var i = 0; i < sortedSlots.length; i++)
      TimeSlot(
        index: i + 1,
        startMinutes: sortedSlots[i].$1,
        endMinutes: sortedSlots[i].$2,
      ),
  ];
  final sectionOf = {
    for (var i = 0; i < sortedSlots.length; i++) sortedSlots[i]: i + 1,
  };

  // (星期, 课程名, 节次) -> 周次集合。
  // 先按节次累积周次，enable_day 同时列出「循环第一周的周一」和「第二周的周一」时，
  // 单周 + 双周会在这里合并成「每周」，而不是留下两条看起来重复的记录。
  final bySection = <(int, String, int), Set<int>>{};

  for (final sch in schedules) {
    if (sch is! Map) continue;
    final schName = '${sch['name'] ?? ''}';
    final enableDays = sch['enable_day'];
    if (enableDays is! List || enableDays.isEmpty) {
      warnings.add('课表「$schName」没有 enable_day，已跳过');
      continue;
    }
    for (final raw in enableDays) {
      final workDay = raw is int ? raw : int.tryParse('$raw');
      if (workDay == null) continue;
      final placed = layout.map[workDay];
      if (placed == null) {
        warnings.add('课表「$schName」的 enable_day=$workDay 超出循环的工作日数，已跳过');
        continue;
      }
      final day = placed.weekday;
      final weeks = switch (layout.weeksInCycle) {
        2 => placed.weekInCycle == 1 ? oddWeeks(totalWeeks) : evenWeeks(totalWeeks),
        _ => allWeeks(totalWeeks),
      };

      for (final c in (sch['classes'] as List? ?? const [])) {
        if (c is! Map) continue;
        final name = '${c['subject'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final start = _minutes(c['start_time']);
        final end = _minutes(c['end_time']);
        if (start == null || end == null) {
          warnings.add('课表「$schName」的「$name」时间格式不对，已跳过');
          continue;
        }
        final section = sectionOf[(start, end)];
        if (section == null) continue;
        bySection.putIfAbsent((day, name, section), () => <int>{}).addAll(weeks);
      }
    }
  }

  final courses = mergeCourseInfos([
    for (final entry in bySection.entries)
      CourseInfoDto(
        name: entry.key.$2,
        day: entry.key.$1,
        weeks: entry.value.toList()..sort(),
        sections: [entry.key.$3],
        teacher: subjectInfo[entry.key.$2]?.teacher,
        position: subjectInfo[entry.key.$2]?.location,
      ),
  ]);

  if (courses.isEmpty) throw const FormatException('CSES 里没有解析出任何课程');

  return ImportedSchedule(
    courses: courses,
    warnings: warnings,
    name: _orNull(config['name']),
    totalWeeks: totalWeeks,
    timeSlots: timeSlots.isEmpty ? null : timeSlots,
  );
}

/// 把「循环中的第 N 个工作日」映射成 (星期几, 第几个循环周)。
({Map<int, ({int weekday, int weekInCycle})> map, int weeksInCycle}) _resolveCycle(
    Map cycle) {
  var spans = (cycle['spans'] as List?)
          ?.whereType<Map>()
          .map((s) => (
                activity: '${s['activity'] ?? 'work'}',
                count: s['count'] is int ? s['count'] as int : int.tryParse('${s['count']}') ?? 0,
              ))
          .where((s) => s.count > 0)
          .toList() ??
      const [];

  if (spans.isEmpty) {
    // 没写 spans 就按「连续工作 work_count 天，再休息 rest_count 天」处理。
    final work = cycle['work_count'] is int ? cycle['work_count'] as int : 5;
    final rest = cycle['rest_count'] is int ? cycle['rest_count'] as int : 2;
    spans = [(activity: 'work', count: work), (activity: 'rest', count: rest)];
  }

  final map = <int, ({int weekday, int weekInCycle})>{};
  var calendarDay = 0;
  var workIndex = 0;
  for (final span in spans) {
    if (span.activity == 'work') {
      for (var i = 0; i < span.count; i++) {
        workIndex++;
        map[workIndex] = (
          weekday: calendarDay % 7 + 1,
          weekInCycle: calendarDay ~/ 7 + 1,
        );
        calendarDay++;
      }
    } else {
      calendarDay += span.count;
    }
  }

  if (calendarDay == 0) throw const FormatException('CSES 的 cycle 里没有任何天数');
  if (calendarDay % 7 != 0) {
    throw FormatException('CSES 的循环长度是 $calendarDay 天，不是整数周，'
        '本程序的周次模型无法表达');
  }
  final weeksInCycle = calendarDay ~/ 7;
  if (weeksInCycle > 2) {
    throw FormatException('CSES 是 $weeksInCycle 周循环，本程序只支持 1 周（每周相同）'
        '和 2 周（单双周）循环');
  }
  return (map: map, weeksInCycle: weeksInCycle);
}

int? _minutes(Object? value) {
  if (value is! String) return null;
  try {
    return parseMinutes(value);
  } on FormatException {
    return null;
  }
}

String? _orNull(Object? value) {
  if (value == null) return null;
  final t = '$value'.trim();
  return t.isEmpty ? null : t;
}
