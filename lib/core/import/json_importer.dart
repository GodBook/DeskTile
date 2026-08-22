import 'dart:convert';

import '../models/time_slot.dart';
import 'course_info_dto.dart';

/// 导入小爱课程表风格的 JSON。
///
/// 接受两种形状：
///   {"courseInfos": [...], "sectionTimes": [...]}
///   [...]                                        （直接是 courseInfos 数组）
///
/// 这也是将来接教务系统直连时的落地格式 —— 社区 `.js` 解析器的输出可以原样粘进来。
ImportedSchedule importCourseInfosJson(String content, {int totalWeeks = 20}) {
  final decoded = jsonDecode(content);
  final List<dynamic> rawCourses;
  List<dynamic>? rawTimes;
  String? name;

  if (decoded is List) {
    rawCourses = decoded;
  } else if (decoded is Map<String, dynamic>) {
    final ci = decoded['courseInfos'] ?? decoded['courses'];
    if (ci is! List) {
      throw const FormatException('JSON 里找不到 courseInfos 数组');
    }
    rawCourses = ci;
    final st = decoded['sectionTimes'];
    if (st is List) rawTimes = st;
    name = decoded['name'] is String ? decoded['name'] as String : null;
  } else {
    throw const FormatException('JSON 顶层既不是数组也不是对象');
  }

  final warnings = <String>[];
  final courses = <CourseInfoDto>[];
  for (var i = 0; i < rawCourses.length; i++) {
    final item = rawCourses[i];
    if (item is! Map<String, dynamic>) {
      warnings.add('第 ${i + 1} 条记录不是对象，已跳过');
      continue;
    }
    final dto = CourseInfoDto.fromAiSchedule(item);
    if (dto.name.isEmpty) {
      warnings.add('第 ${i + 1} 条记录没有课程名，已跳过');
      continue;
    }
    courses.add(dto);
  }
  if (courses.isEmpty) throw const FormatException('JSON 里没有解析出任何课程');

  return ImportedSchedule(
    courses: courses,
    warnings: warnings,
    name: name,
    totalWeeks: totalWeeks,
    timeSlots: _parseSectionTimes(rawTimes, warnings),
  );
}

/// sectionTimes: [{"section":1,"startTime":"08:00","endTime":"08:45"}, ...]
List<TimeSlot>? _parseSectionTimes(List<dynamic>? raw, List<String> warnings) {
  if (raw == null || raw.isEmpty) return null;
  final slots = <TimeSlot>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final section = item['section'];
    final start = item['startTime'] ?? item['start'];
    final end = item['endTime'] ?? item['end'];
    if (section is! int || start is! String || end is! String) continue;
    try {
      slots.add(TimeSlot(
        index: section,
        startMinutes: parseMinutes(start),
        endMinutes: parseMinutes(end),
      ));
    } on FormatException {
      warnings.add('第 $section 节的时间「$start-$end」格式不对，已忽略');
    }
  }
  if (slots.isEmpty) return null;
  slots.sort((a, b) => a.index.compareTo(b.index));
  return slots;
}
