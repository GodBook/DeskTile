import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/import/course_info_dto.dart';
import 'package:desktile/core/import/csv_importer.dart';
import 'package:desktile/core/import/ics_importer.dart';
import 'package:desktile/core/import/json_importer.dart';
import 'package:desktile/core/week_math.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    utf8.decode(File('docs/$name').readAsBytesSync());

void main() {
  group('CSV 导入', () {
    final imported = importCsv(_fixture('示例课表.csv'), totalWeeks: 16);

    test('9 条记录全部解析成功，没有警告', () {
      expect(imported.courses.length, 9);
      expect(imported.warnings, isEmpty);
    });

    test('中文星期和数字星期都认', () {
      final byName = {for (final c in imported.courses) '${c.name}|${c.day}': c};
      expect(byName.containsKey('大学英语|1'), isTrue);
      expect(byName.containsKey('程序设计基础|4'), isTrue);
    });

    test('单双周正确展开', () {
      final linear = imported.courses.firstWhere((c) => c.name == '线性代数');
      expect(linear.weeks.toSet(), oddWeeks(16));
      final pe = imported.courses.firstWhere((c) => c.name == '体育');
      expect(pe.weeks.toSet(), evenWeeks(16));
    });

    test('节次区间展开', () {
      final prog = imported.courses.firstWhere((c) => c.name == '程序设计基础');
      expect(prog.sections, [1, 2, 3, 4]);
      expect(prog.position, '机房-A302');
    });

    test('部分周次', () {
      final prob = imported.courses.firstWhere((c) => c.name == '概率论与数理统计');
      expect(prob.weeks, [9, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('装配成课表：同名课合并成一门，时段各自独立', () {
      final warnings = <String>[];
      final t = buildTimetable(
        id: 't',
        name: '导入的课表',
        termStart: DateTime(2026, 9, 7),
        imported: imported,
        warnings: warnings,
        totalWeeks: 16,
      );
      expect(t.courses.length, 8, reason: '高等数学A 出现两次，应合并为一门课');
      expect(t.sessions.length, 9);
      expect(warnings, isEmpty);

      final math = t.courses.firstWhere((c) => c.name == '高等数学A');
      final mathSessions = t.sessions.where((s) => s.courseId == math.id).toList();
      expect(mathSessions.length, 2);
      expect(mathSessions.map((s) => s.day).toSet(), {1, 4});

      final prog = t.sessions.firstWhere((s) =>
          t.courseById(s.courseId)!.name == '程序设计基础');
      expect(prog.startSection, 1);
      expect(prog.endSection, 4);
    });

    test('缺列时给出可读的错误', () {
      expect(
        () => importCsv('课程名称,星期\n数学,1\n'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('周次'), contains('节次')),
        )),
      );
    });

    test('坏行进警告而不是让整份导入失败', () {
      final result = importCsv(
        '课程名称,星期,节次,周次\n'
        '数学,周一,1-2,1-16\n'
        '语文,火星日,1-2,1-16\n'
        '英语,周三,1-2,随便\n',
        totalWeeks: 16,
      );
      expect(result.courses.length, 1);
      expect(result.warnings.length, 2);
      expect(result.warnings[0], contains('语文'));
      expect(result.warnings[1], contains('英语'));
    });
  });

  group('小爱课程表 JSON 导入', () {
    const json = '''
{
  "courseInfos": [
    {"name":"高等数学","teacher":"张伟","position":"教三-305","day":1,
     "weeks":[1,2,3],"sections":[{"section":1},{"section":2}]},
    {"name":"大学英语","position":"外语楼-201","day":3,
     "weeks":[1,3,5],"sections":[3,4]}
  ],
  "sectionTimes": [
    {"section":1,"startTime":"08:00","endTime":"08:45"},
    {"section":2,"startTime":"08:50","endTime":"09:35"}
  ]
}
''';

    test('sections 支持对象和纯数字两种写法', () {
      final r = importCourseInfosJson(json, totalWeeks: 16);
      expect(r.courses.length, 2);
      expect(r.courses[0].sections, [1, 2]);
      expect(r.courses[1].sections, [3, 4]);
      expect(r.courses[0].position, '教三-305');
    });

    test('sectionTimes 变成节次时间表', () {
      final r = importCourseInfosJson(json, totalWeeks: 16);
      expect(r.timeSlots, isNotNull);
      expect(r.timeSlots!.length, 2);
      expect(r.timeSlots!.first.startText, '08:00');
    });

    test('顶层直接是数组也能导', () {
      final r = importCourseInfosJson(
        '[{"name":"体育","day":5,"weeks":[2,4],"sections":[{"section":7}]}]',
        totalWeeks: 16,
      );
      expect(r.courses.single.name, '体育');
      expect(r.courses.single.sections, [7]);
    });

    test('DTO 能往返', () {
      final dto = importCourseInfosJson(json).courses.first;
      final back = CourseInfoDto.fromAiSchedule(dto.toAiSchedule());
      expect(back.name, dto.name);
      expect(back.sections, dto.sections);
      expect(back.weeks, dto.weeks);
    });

    test('空的 courseInfos 报错', () {
      expect(() => importCourseInfosJson('{"courseInfos":[]}'),
          throwsFormatException);
    });
  });

  group('ICS 导入', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//DeskTile//Test//CN
BEGIN:VEVENT
UID:1
SUMMARY:高等数学
LOCATION:教三-305
DTSTART:20260907T080000
DTEND:20260907T093500
END:VEVENT
BEGIN:VEVENT
UID:2
SUMMARY:高等数学
LOCATION:教三-305
DTSTART:20260914T080000
DTEND:20260914T093500
END:VEVENT
BEGIN:VEVENT
UID:3
SUMMARY:线性代数
LOCATION:教三-208
DTSTART:20260908T100000
DTEND:20260908T113500
END:VEVENT
END:VCALENDAR
''';

    test('学期第一周周一按最早事件推算', () {
      final r = importIcs(ics);
      expect(r.termStart, DateTime(2026, 9, 7));
      expect(r.totalWeeks, 2);
    });

    test('同一门课的多次事件归并成一个时段 + 一组周次', () {
      final r = importIcs(ics);
      final math = r.courses.firstWhere((c) => c.name == '高等数学');
      expect(math.day, 1);
      expect(math.weeks, [1, 2]);
      expect(math.position, '教三-305');
    });

    test('节次时间表按时间段推算', () {
      final r = importIcs(ics);
      expect(r.timeSlots!.length, 2);
      expect(r.timeSlots![0].startText, '08:00');
      expect(r.timeSlots![1].startText, '10:00');
    });

    test('没有事件时报错', () {
      expect(
        () => importIcs('BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:x\nEND:VCALENDAR\n'),
        throwsFormatException,
      );
    });
  });
}
