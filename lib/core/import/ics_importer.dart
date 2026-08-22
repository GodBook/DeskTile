import 'package:icalendar_parser/icalendar_parser.dart';

import '../models/time_slot.dart';
import '../week_math.dart';
import 'course_info_dto.dart';

/// 导入 ICS（iCalendar）。
///
/// 面向的是「教务系统把每一次课都导出成一条 VEVENT」这种最常见的格式：
/// 学期第一周的周一按最早的一条事件推算，节次时间表按文件里出现过的时间段推算，
/// 同一门课在同一星期同一时间段的多条事件会被归并成一个时段 + 一组周次。
///
/// 带 RRULE 的重复事件不会展开（只当作一次），会在警告里说明。
ImportedSchedule importIcs(String content) {
  final warnings = <String>[];
  final ical = ICalendar.fromString(content);

  final events = <({DateTime start, DateTime end, String summary, String? location})>[];
  var sawRrule = false;

  for (final component in ical.data) {
    if (component['type'] != 'VEVENT') continue;
    if (component['rrule'] != null) sawRrule = true;

    final summary = '${component['summary'] ?? ''}'.trim();
    if (summary.isEmpty) continue;

    final dtstart = component['dtstart'];
    final dtend = component['dtend'];
    if (dtstart is! IcsDateTime) continue;
    final start = dtstart.toDateTime();
    if (start == null) continue;
    final end = (dtend is IcsDateTime ? dtend.toDateTime() : null) ??
        start.add(const Duration(minutes: 45));

    events.add((
      start: start.isUtc ? start.toLocal() : start,
      end: end.isUtc ? end.toLocal() : end,
      summary: summary,
      location: _orNull(component['location']),
    ));
  }

  if (events.isEmpty) throw const FormatException('ICS 里没有可用的课程事件');
  if (sawRrule) {
    warnings.add('文件里有 RRULE 重复规则，本程序不展开重复，只按单次事件处理，'
        '导入后请核对周次');
  }

  events.sort((a, b) => a.start.compareTo(b.start));
  final termStart = mondayOf(events.first.start);
  final lastDay = events.last.start;
  final totalWeeks = (daysBetween(termStart, lastDay) ~/ 7) + 1;

  // 节次时间表按出现过的时间段推算。
  final slotKeys = <(int, int)>{};
  for (final e in events) {
    slotKeys.add((_minutesOf(e.start), _minutesOf(e.end)));
  }
  final sorted = slotKeys.toList()
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  final timeSlots = [
    for (var i = 0; i < sorted.length; i++)
      TimeSlot(index: i + 1, startMinutes: sorted[i].$1, endMinutes: sorted[i].$2),
  ];
  final sectionOf = {for (var i = 0; i < sorted.length; i++) sorted[i]: i + 1};
  warnings.add('节次时间表是从 ICS 的时间段推算出来的（共 ${timeSlots.length} 段），'
      '一段可能对应现实中的连续两节课，可在设置里调整');

  final grouped = <String,
      ({int day, int section, String name, String? location, Set<int> weeks})>{};

  for (final e in events) {
    final wd = weekDayOfDate(termStart, e.start, totalWeeks);
    if (wd == null) continue;
    final section = sectionOf[(_minutesOf(e.start), _minutesOf(e.end))];
    if (section == null) continue;

    final key = '${wd.day}|$section|${e.summary}|${e.location ?? ''}';
    final entry = grouped.putIfAbsent(
      key,
      () => (
        day: wd.day,
        section: section,
        name: e.summary,
        location: e.location,
        weeks: <int>{},
      ),
    );
    entry.weeks.add(wd.week);
  }

  final courses = mergeCourseInfos([
    for (final g in grouped.values)
      CourseInfoDto(
        name: g.name,
        day: g.day,
        weeks: g.weeks.toList()..sort(),
        sections: [g.section],
        position: g.location,
      ),
  ]);

  return ImportedSchedule(
    courses: courses,
    warnings: warnings,
    termStart: termStart,
    totalWeeks: totalWeeks,
    timeSlots: timeSlots,
  );
}

int _minutesOf(DateTime d) => d.hour * 60 + d.minute;

String? _orNull(Object? value) {
  if (value == null) return null;
  final t = '$value'.trim();
  return t.isEmpty ? null : t;
}
