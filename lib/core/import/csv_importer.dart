import 'package:csv/csv.dart';

import '../weeks_parser.dart';
import 'course_info_dto.dart';
import 'field_parsers.dart';

/// 表头别名。教务系统导出的表格列名五花八门，这里尽量都认。
const _aliases = <String, List<String>>{
  'name': ['课程名称', '课程名', '课程', '名称', 'name', 'course', 'coursename'],
  'teacher': ['教师', '老师', '授课教师', '任课教师', 'teacher'],
  'room': ['教室', '地点', '上课地点', '上课教室', '教学楼', 'position', 'room', 'location'],
  'day': ['星期', '周几', '星期几', '上课星期', 'day', 'weekday'],
  'startSection': ['开始节次', '起始节次', '开始节', '起始节', 'start', 'startsection'],
  'endSection': ['结束节次', '终止节次', '结束节', '末节', 'end', 'endsection'],
  'sections': ['节次', '上课节次', '节数', 'sections', 'section'],
  'weeks': ['周次', '上课周次', '周数', '周', 'weeks', 'week'],
};

/// 导入 CSV。模板见 docs/课表模板.csv。
///
/// 必需列：课程名称、星期、周次，以及节次信息（`节次` 一列写 "1-2"，
/// 或者 `开始节次`+`结束节次` 两列）。
ImportedSchedule importCsv(String content, {int totalWeeks = 20}) {
  final warnings = <String>[];
  final normalized =
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rows = Csv(skipEmptyLines: true).decode(normalized);

  final dataRows = rows.where((r) => r.any((c) => '$c'.trim().isNotEmpty)).toList();
  if (dataRows.isEmpty) {
    throw const FormatException('CSV 是空的');
  }

  final header = dataRows.first.map((c) => '$c'.trim().toLowerCase()).toList();
  final index = <String, int>{};
  for (final entry in _aliases.entries) {
    for (var i = 0; i < header.length; i++) {
      if (entry.value.contains(header[i])) {
        index[entry.key] = i;
        break;
      }
    }
  }

  final missing = <String>[];
  if (!index.containsKey('name')) missing.add('课程名称');
  if (!index.containsKey('day')) missing.add('星期');
  if (!index.containsKey('weeks')) missing.add('周次');
  if (!index.containsKey('sections') && !index.containsKey('startSection')) {
    missing.add('节次（或 开始节次+结束节次）');
  }
  if (missing.isNotEmpty) {
    throw FormatException('CSV 缺少必需的列：${missing.join('、')}。'
        '实际表头：${header.join('、')}');
  }

  String cell(List<dynamic> row, String key) {
    final i = index[key];
    if (i == null || i >= row.length) return '';
    return '${row[i]}'.trim();
  }

  final courses = <CourseInfoDto>[];
  for (var r = 1; r < dataRows.length; r++) {
    final row = dataRows[r];
    final lineNo = r + 1;
    final name = cell(row, 'name');
    if (name.isEmpty) continue;

    final day = parseWeekDay(cell(row, 'day'));
    if (day == null) {
      warnings.add('第 $lineNo 行「$name」：星期「${cell(row, 'day')}」看不懂，已跳过');
      continue;
    }

    List<int> sections;
    if (index.containsKey('sections') && cell(row, 'sections').isNotEmpty) {
      sections = parseSections(cell(row, 'sections'));
    } else {
      final start = int.tryParse(cell(row, 'startSection'));
      final end = int.tryParse(cell(row, 'endSection')) ?? start;
      if (start == null || end == null) {
        warnings.add('第 $lineNo 行「$name」：节次读不出来，已跳过');
        continue;
      }
      sections = [for (var s = start; s <= end; s++) s];
    }
    if (sections.isEmpty) {
      warnings.add('第 $lineNo 行「$name」：节次为空，已跳过');
      continue;
    }

    final weeks = tryParseWeeks(cell(row, 'weeks'), totalWeeks: totalWeeks);
    if (weeks == null) {
      warnings.add('第 $lineNo 行「$name」：周次「${cell(row, 'weeks')}」看不懂，已跳过');
      continue;
    }

    courses.add(CourseInfoDto(
      name: name,
      day: day,
      weeks: weeks.toList()..sort(),
      sections: sections,
      teacher: _orNull(cell(row, 'teacher')),
      position: _orNull(cell(row, 'room')),
    ));
  }

  if (courses.isEmpty) {
    throw FormatException('CSV 里没有解析出任何课程。'
        '${warnings.isEmpty ? '' : '问题：${warnings.first}'}');
  }
  return ImportedSchedule(
    courses: courses,
    warnings: warnings,
    totalWeeks: totalWeeks,
  );
}

String? _orNull(String s) => s.isEmpty ? null : s;
