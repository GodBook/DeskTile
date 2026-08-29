import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/import/course_info_dto.dart';
import 'package:desktile/core/import/cses_importer.dart';
import 'package:desktile/core/import/exporter.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:desktile/core/week_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String _fixture(String name) =>
    utf8.decode(File('docs/$name').readAsBytesSync());

void main() {
  group('CSES 导入', () {
    final imported = importCses(_fixture('示例课表.cses.yaml'), totalWeeks: 16);

    test('取到配置名', () {
      expect(imported.name, 'CSES 导入测试');
    });

    test('节次时间表从时间段推出来', () {
      expect(imported.timeSlots!.length, 2);
      expect(imported.timeSlots![0].startText, '08:00');
      expect(imported.timeSlots![1].startText, '08:50');
    });

    test('enable_day 同时给出两个循环周 -> 合并成每周', () {
      final monMath = imported.courses.firstWhere(
        (c) => c.name == '数学' && c.day == 1,
      );
      expect(monMath.weeks.toSet(), allWeeks(16));
      expect(monMath.sections, [1]);
      expect(monMath.teacher, '李梅');
      expect(monMath.position, '101');
    });

    test('只在循环第一周出现 -> 单周', () {
      final tueMath = imported.courses.firstWhere(
        (c) => c.name == '数学' && c.day == 2,
      );
      expect(tueMath.weeks.toSet(), oddWeeks(16));
    });

    test('课程数：周一数学/周一语文/周二数学', () {
      expect(imported.courses.length, 3);
    });

    test('循环不是整数周时明确报错', () {
      const bad = '''
version: 2
configuration:
  name: "x"
  description: "x"
  cycle:
    work_count: 4
    rest_count: 2
    spans:
      - activity: work
        count: 4
      - activity: rest
        count: 2
subjects:
  - name: "数学"
schedules:
  - name: "d1"
    enable_day: [1]
    classes:
      - subject: "数学"
        start_time: "08:00:00"
        end_time: "08:40:00"
''';
      expect(
        () => importCses(bad),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('不是整数周'),
          ),
        ),
      );
    });

    test('三周以上循环明确报错', () {
      const bad = '''
version: 2
configuration:
  name: "x"
  description: "x"
  cycle:
    work_count: 15
    rest_count: 6
    spans:
      - activity: work
        count: 5
      - activity: rest
        count: 2
      - activity: work
        count: 5
      - activity: rest
        count: 2
      - activity: work
        count: 5
      - activity: rest
        count: 2
subjects:
  - name: "数学"
schedules:
  - name: "d1"
    enable_day: [1]
    classes:
      - subject: "数学"
        start_time: "08:00:00"
        end_time: "08:40:00"
''';
      expect(
        () => importCses(bad),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('3 周循环'),
          ),
        ),
      );
    });
  });

  group('CSES 导出', () {
    final t = buildTestTimetable();
    final export = exportCses(t);

    test('含单周课时导出两周循环', () {
      expect(export.yaml, contains('work_count: 10'));
      expect(export.yaml, contains('rest_count: 4'));
      expect(export.warnings, isEmpty);
    });

    test('单双周各自一张日课表', () {
      expect(export.yaml, contains('name: "周二-单周"'));
    });

    test('subjects 带上教师和教室', () {
      expect(export.yaml, contains('teacher: "张伟"'));
      expect(export.yaml, contains('location: "教三-305"'));
    });

    test('导出再导入，星期和周次保持一致', () {
      final back = importCses(export.yaml, totalWeeks: t.totalWeeks);
      final merged = mergeCourseInfos(back.courses);

      final math = merged.firstWhere((c) => c.name == '高等数学');
      expect(math.day, 1);
      expect(math.weeks.toSet(), allWeeks(t.totalWeeks));
      expect(math.sections.length, 2);

      final linear = merged.firstWhere((c) => c.name == '线性代数');
      expect(linear.day, 2);
      expect(linear.weeks.toSet(), oddWeeks(t.totalWeeks));

      final afternoon = merged.firstWhere((c) => c.name == '下午的课');
      expect(afternoon.day, 3);
      expect(afternoon.sections.length, 2);
    });

    test('周次不是每周/单周/双周的时段会被跳过并给出警告', () {
      final odd = t.copyWith(
        sessions: [
          t.sessions.first.copyWith(weeks: {1, 2, 5, 9}),
          ...t.sessions.skip(1),
        ],
      );
      final result = exportCses(odd);
      expect(result.warnings.single, contains('高等数学'));
      expect(result.yaml, isNot(contains('"高等数学"')));
    });

    test('临时安排无法表达时明确提示使用 JSON 备份', () {
      final changed = t.copyWith(
        scheduleChanges: [
          ScheduleChange.cancellation(
            id: 'cancel',
            originalSessionId: 's1',
            originalDate: DateTime(2026, 9, 7),
          ),
        ],
      );
      final result = exportCses(changed);
      expect(result.warnings.single, contains('JSON 备份'));
    });

    test('有周日的课时明确拒绝导出', () {
      final withSunday = t.copyWith(
        sessions: [t.sessions.first.copyWith(day: 7)],
      );
      expect(
        () => exportCses(withSunday),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('周日'),
          ),
        ),
      );
    });
  });
}
