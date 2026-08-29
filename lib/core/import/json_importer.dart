import 'dart:convert';

import '../models/schedule_change.dart';
import '../models/task_item.dart';
import '../models/time_slot.dart';
import '../models/timetable.dart';
import '../week_math.dart';
import 'course_info_dto.dart';

/// 导入小爱课程表风格的 JSON。
///
/// 接受以下几种形状：
///   {"courseInfos": [...], "sectionTimes": [...]}
///   [...]                                        （直接是 courseInfos 数组）
///   {"timetables": [...], "activeTimetableId": "..."}（本程序备份）
///
/// 这也是将来接教务系统直连时的落地格式 —— 社区 `.js` 解析器的输出可以原样粘进来。
ImportedSchedule importCourseInfosJson(String content, {int totalWeeks = 20}) {
  // Windows 上用户可能会用带 BOM 的编辑器转存文件；jsonDecode 不接受 BOM。
  final decoded = jsonDecode(_stripUtf8Bom(content));
  final warnings = <String>[];
  final payload = _readPayload(
    decoded,
    fallbackTotalWeeks: totalWeeks,
    warnings: warnings,
  );

  final courses = <CourseInfoDto>[];
  for (var i = 0; i < payload.rawCourses.length; i++) {
    final item = payload.rawCourses[i];
    if (item is! Map) {
      warnings.add('第 ${i + 1} 条记录不是对象，已跳过');
      continue;
    }
    try {
      final dto = CourseInfoDto.fromAiSchedule(Map<String, dynamic>.from(item));
      if (dto.name.isEmpty) {
        warnings.add('第 ${i + 1} 条记录没有课程名，已跳过');
        continue;
      }
      courses.add(dto);
    } catch (_) {
      // 单条记录损坏时尽量保住同一文件里的其它课程。
      warnings.add('第 ${i + 1} 条记录格式不正确，已跳过');
    }
  }
  if (courses.isEmpty) throw const FormatException('JSON 里没有解析出任何课程');

  return ImportedSchedule(
    courses: courses,
    warnings: warnings,
    name: payload.name,
    termStart: payload.termStart,
    totalWeeks: payload.totalWeeks,
    timeSlots: _parseSectionTimes(payload.rawTimes, warnings),
    sourceTimetable: payload.sourceTimetable,
    tasks: payload.tasks,
  );
}

class _JsonPayload {
  const _JsonPayload({
    required this.rawCourses,
    required this.totalWeeks,
    this.rawTimes,
    this.name,
    this.termStart,
    this.sourceTimetable,
    this.tasks,
  });

  final List<dynamic> rawCourses;
  final List<dynamic>? rawTimes;
  final String? name;
  final DateTime? termStart;
  final int totalWeeks;
  final Timetable? sourceTimetable;
  final List<TaskItem>? tasks;
}

_JsonPayload _readPayload(
  Object? decoded, {
  required int fallbackTotalWeeks,
  required List<String> warnings,
}) {
  if (decoded is List) {
    return _JsonPayload(rawCourses: decoded, totalWeeks: fallbackTotalWeeks);
  }
  if (decoded is! Map) {
    throw const FormatException('JSON 顶层既不是数组也不是对象');
  }

  final root = Map<String, dynamic>.from(decoded);
  // AppData.toJson() 的备份格式：课程定义和上课时段分开存储。
  if (root.containsKey('timetables')) {
    return _readBackupPayload(
      root,
      fallbackTotalWeeks: fallbackTotalWeeks,
      warnings: warnings,
    );
  }
  // 也接受直接导出的单张 Timetable（没有 AppData 外壳）。
  if (root['courses'] is List && root['sessions'] is List) {
    return _payloadFromTimetable(
      root,
      fallbackTotalWeeks: fallbackTotalWeeks,
      warnings: warnings,
    );
  }

  final rawCourses = root['courseInfos'] ?? root['courses'];
  if (rawCourses is! List) {
    throw const FormatException('JSON 里找不到 courseInfos 数组');
  }
  return _JsonPayload(
    rawCourses: rawCourses,
    rawTimes: root['sectionTimes'] is List
        ? root['sectionTimes'] as List<dynamic>
        : null,
    name: root['name'] is String ? root['name'] as String : null,
    termStart: _parseDate(root['termStart']),
    totalWeeks: _positiveInt(root['totalWeeks']) ?? fallbackTotalWeeks,
  );
}

_JsonPayload _readBackupPayload(
  Map<String, dynamic> root, {
  required int fallbackTotalWeeks,
  required List<String> warnings,
}) {
  final rawTimetables = root['timetables'];
  if (rawTimetables is! List) {
    throw const FormatException('备份 JSON 里的 timetables 不是数组');
  }

  final timetables = <Map<String, dynamic>>[];
  for (var i = 0; i < rawTimetables.length; i++) {
    final item = rawTimetables[i];
    if (item is! Map) {
      warnings.add('备份中的第 ${i + 1} 张课表不是对象，已忽略');
      continue;
    }
    try {
      timetables.add(Map<String, dynamic>.from(item));
    } catch (_) {
      warnings.add('备份中的第 ${i + 1} 张课表格式不正确，已忽略');
    }
  }
  if (timetables.isEmpty) {
    throw const FormatException('备份 JSON 里没有可导入的课表');
  }

  final activeId = _nonEmptyString(root['activeTimetableId']);
  Map<String, dynamic>? selected;
  if (activeId != null) {
    for (final timetable in timetables) {
      if (timetable['id'] == activeId) {
        selected = timetable;
        break;
      }
    }
    if (selected == null) {
      warnings.add('备份中找不到活动课表，已使用第一张课表');
    }
  }
  selected ??= timetables.first;

  return _payloadFromTimetable(
    selected,
    fallbackTotalWeeks: fallbackTotalWeeks,
    warnings: warnings,
    tasks: _readBackupTasks(root, warnings),
  );
}

List<TaskItem>? _readBackupTasks(
  Map<String, dynamic> root,
  List<String> warnings,
) {
  if (!root.containsKey('tasks')) return null;
  final rawTasks = root['tasks'];
  if (rawTasks is! List) {
    warnings.add('备份中的作业与待办格式不正确，已保留当前任务列表');
    return null;
  }
  final tasks = <TaskItem>[];
  for (var index = 0; index < rawTasks.length; index++) {
    final item = rawTasks[index];
    if (item is! Map) {
      warnings.add('备份中的第 ${index + 1} 项作业或待办格式不正确，已忽略');
      continue;
    }
    try {
      tasks.add(TaskItem.fromJson(Map<String, dynamic>.from(item)));
    } catch (_) {
      warnings.add('备份中的第 ${index + 1} 项作业或待办格式不正确，已忽略');
    }
  }
  return tasks;
}

_JsonPayload _payloadFromTimetable(
  Map<String, dynamic> table, {
  required int fallbackTotalWeeks,
  required List<String> warnings,
  List<TaskItem>? tasks,
}) {
  final rawTimes = table['timeSlots'] is List
      ? table['timeSlots'] as List<dynamic>
      : null;
  final rawCourses = <dynamic>[..._backupCourseRecords(table, warnings)];
  Timetable? sourceTimetable;
  try {
    sourceTimetable = Timetable.fromJson(table);
  } catch (_) {
    final changes = table['scheduleChanges'];
    if (changes is List && changes.isNotEmpty) {
      warnings.add('备份中的临时安排无法完整恢复，已按普通课表导入');
    }
  }
  if (rawCourses.isEmpty && sourceTimetable != null) {
    rawCourses.addAll(_standaloneExtraClassRecords(sourceTimetable));
  }
  return _JsonPayload(
    rawCourses: rawCourses,
    rawTimes: rawTimes,
    name: _nonEmptyString(table['name']),
    termStart: _parseDate(table['termStart']),
    totalWeeks: _positiveInt(table['totalWeeks']) ?? fallbackTotalWeeks,
    sourceTimetable: sourceTimetable,
    tasks: tasks,
  );
}

List<dynamic> _standaloneExtraClassRecords(Timetable timetable) {
  final records = <dynamic>[];
  for (final change in timetable.scheduleChanges) {
    final date = change.targetDate;
    final start = change.startSection;
    final end = change.endSection;
    final course = timetable.courseById(change.courseId ?? '');
    if (change.type != ScheduleChangeType.extraClass ||
        date == null ||
        start == null ||
        end == null ||
        course == null) {
      continue;
    }
    final weekDay = weekDayOfDate(
      timetable.termStart,
      date,
      timetable.totalWeeks,
    );
    if (weekDay == null) continue;
    records.add({
      'name': course.name,
      'teacher': course.teacher ?? '',
      'position': change.room ?? '',
      'day': weekDay.day,
      'weeks': [weekDay.week],
      'sections': [
        for (var section = start; section <= end; section++) section,
      ],
    });
  }
  return records;
}

/// 把备份里的 courses + sessions 还原成 courseInfos 形状。
List<dynamic> _backupCourseRecords(
  Map<String, dynamic> timetable,
  List<String> warnings,
) {
  // 允许未来/旧版本直接在课表对象里保存 courseInfos。
  final embedded = timetable['courseInfos'];
  if (embedded is List && embedded.isNotEmpty) return embedded;

  final definitions = <String, Map<String, dynamic>>{};
  final rawDefinitions = timetable['courses'];
  if (rawDefinitions is List) {
    for (final item in rawDefinitions) {
      if (item is! Map) continue;
      try {
        final definition = Map<String, dynamic>.from(item);
        final id = _nonEmptyString(definition['id']);
        if (id != null) definitions[id] = definition;
      } catch (_) {
        // sessions 仍可能自带课程名，留给下面的兜底路径处理。
      }
    }
  }

  final rawSessions = timetable['sessions'];
  if (rawSessions is! List || rawSessions.isEmpty) {
    // 兼容把 courses 本身当作 courseInfos 保存的早期/第三方备份。
    if (rawDefinitions is List &&
        rawDefinitions.any(
          (item) =>
              item is Map &&
              (item['day'] != null ||
                  item['weeks'] != null ||
                  item['sections'] != null),
        )) {
      return rawDefinitions;
    }
    return const <dynamic>[];
  }

  final records = <dynamic>[];
  for (var i = 0; i < rawSessions.length; i++) {
    final item = rawSessions[i];
    if (item is! Map) {
      warnings.add('备份中的第 ${i + 1} 个上课时段不是对象，已忽略');
      continue;
    }
    final session = Map<String, dynamic>.from(item);
    final courseId = _nonEmptyString(session['courseId']);
    final definition = courseId == null ? null : definitions[courseId];
    final name =
        _nonEmptyString(definition?['name']) ??
        _nonEmptyString(session['name']);
    if (name == null) {
      warnings.add('备份中的第 ${i + 1} 个上课时段找不到课程，已忽略');
      continue;
    }

    final day = _asInt(session['day']);
    final weeks = _asIntList(session['weeks']);
    final sections = _sessionSections(session);
    if (day == null || weeks == null || sections == null || sections.isEmpty) {
      warnings.add('备份中的第 ${i + 1} 个上课时段信息不完整，已忽略');
      continue;
    }

    final teacher =
        _nonEmptyString(session['teacher']) ??
        _nonEmptyString(definition?['teacher']);
    final position =
        _nonEmptyString(session['room']) ??
        _nonEmptyString(definition?['position']) ??
        _nonEmptyString(definition?['room']) ??
        _nonEmptyString(definition?['location']);
    final record = <String, dynamic>{
      'name': name,
      'day': day,
      'weeks': weeks,
      'sections': sections,
    };
    if (teacher != null) record['teacher'] = teacher;
    if (position != null) record['position'] = position;
    records.add(record);
  }
  return records;
}

List<int>? _sessionSections(Map<String, dynamic> session) {
  final start = _asInt(session['startSection']);
  final end = _asInt(session['endSection']);
  if (start != null && end != null) {
    if (start < 1 || end < start) return null;
    return [for (var section = start; section <= end; section++) section];
  }

  final sections = _asSectionList(session['sections']);
  if (sections != null && sections.isNotEmpty) {
    return sections.toSet().toList()..sort();
  }
  final section = _asInt(session['section']);
  return section != null && section > 0 ? [section] : null;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<int>? _asIntList(Object? value) {
  if (value is! List) return null;
  final result = <int>[];
  for (final item in value) {
    final number = _asInt(item);
    if (number == null) return null;
    result.add(number);
  }
  return result;
}

List<int>? _asSectionList(Object? value) {
  if (value is! List) return null;
  final result = <int>[];
  for (final item in value) {
    final number = item is Map ? _asInt(item['section']) : _asInt(item);
    if (number == null) return null;
    result.add(number);
  }
  return result;
}

int? _positiveInt(Object? value) {
  final number = _asInt(value);
  return number != null && number > 0 ? number : null;
}

DateTime? _parseDate(Object? value) {
  final text = _nonEmptyString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

String _stripUtf8Bom(String content) =>
    content.startsWith('\uFEFF') ? content.substring(1) : content;

/// sectionTimes: [{"section":1,"startTime":"08:00","endTime":"08:45"}, ...]
List<TimeSlot>? _parseSectionTimes(List<dynamic>? raw, List<String> warnings) {
  if (raw == null || raw.isEmpty) return null;
  final slots = <TimeSlot>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final section = _asInt(item['section'] ?? item['index']);
    final start = item['startTime'] ?? item['start'];
    final end = item['endTime'] ?? item['end'];
    if (section == null || start is! String || end is! String) continue;
    try {
      slots.add(
        TimeSlot(
          index: section,
          startMinutes: parseMinutes(start),
          endMinutes: parseMinutes(end),
        ),
      );
    } on FormatException {
      warnings.add('第 $section 节的时间「$start-$end」格式不对，已忽略');
    }
  }
  if (slots.isEmpty) return null;
  slots.sort((a, b) => a.index.compareTo(b.index));
  return slots;
}
