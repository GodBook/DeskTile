import 'dart:convert';

import 'package:desktile/core/import/ics_exporter.dart';
import 'package:desktile/core/import/ics_importer.dart';
import 'package:desktile/core/models/academic_calendar_event.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 8, 30, 12, 34, 56);

  test('ICS 导出逐次展开单双周课程并保留时间和教室', () {
    final result = exportIcs(
      buildTestTimetable(totalWeeks: 2),
      generatedAt: generatedAt,
    );
    final events = _events(result.calendar);

    expect(result.eventCount, 7);
    expect(events, hasLength(7));
    expect(result.calendar, isNot(contains('RRULE')));
    expect(result.calendar, contains('DTSTAMP:20260830T123456Z'));
    expect(events.map((event) => event['uid']).toSet(), hasLength(7));

    final math = events.firstWhere((event) => event['summary'] == '高等数学');
    expect(_dateTime(math, 'dtstart'), DateTime(2026, 9, 7, 8));
    expect(_dateTime(math, 'dtend'), DateTime(2026, 9, 7, 9, 35));
    expect(math['location'], '教三-305');
    expect('${math['description']}', contains('教师：张伟'));
    expect('${math['description']}', contains('第1-2节'));

    expect(events.where((event) => event['summary'] == '线性代数'), hasLength(1));
  });

  test('ICS 导出反映停课、调课、补课和校历批量停课', () {
    final timetable = buildTestTimetable(totalWeeks: 2).copyWith(
      scheduleChanges: [
        ScheduleChange.cancellation(
          id: 'cancel-math',
          originalSessionId: 's1',
          originalDate: DateTime(2026, 9, 7),
        ),
        ScheduleChange.reschedule(
          id: 'move-english',
          originalSessionId: 's2',
          originalDate: DateTime(2026, 9, 7),
          targetDate: DateTime(2026, 9, 8),
          startSection: 8,
          endSection: 9,
          room: '临时教室',
        ),
        ScheduleChange.extraClass(
          id: 'extra-linear',
          courseId: 'c3',
          targetDate: DateTime(2026, 9, 14),
          startSection: 3,
          endSection: 4,
          room: '补课教室',
        ),
      ],
      academicCalendarEvents: [
        AcademicCalendarEvent(
          id: 'holiday',
          title: '统一停课',
          type: AcademicCalendarEventType.holiday,
          startDate: DateTime(2026, 9, 14),
          endDate: DateTime(2026, 9, 14),
        ),
      ],
    );

    final result = exportIcs(timetable, generatedAt: generatedAt);
    final events = _events(result.calendar);
    expect(result.eventCount, 5);

    expect(
      events.where(
        (event) =>
            event['summary'] == '高等数学' &&
            _dateTime(event, 'dtstart') == DateTime(2026, 9, 7, 8),
      ),
      isEmpty,
    );
    final moved = events.singleWhere(
      (event) =>
          event['summary'] == '大学英语' && _dateTime(event, 'dtstart').day == 8,
    );
    expect(_dateTime(moved, 'dtstart'), DateTime(2026, 9, 8, 15, 55));
    expect(moved['location'], '临时教室');
    expect('${moved['description']}', contains('临时调课'));

    final onSuspendedDay = events.where(
      (event) => _dateTime(event, 'dtstart').day == 14,
    );
    expect(onSuspendedDay, hasLength(1));
    expect(onSuspendedDay.single['summary'], '线性代数');
    expect(onSuspendedDay.single['location'], '补课教室');
    expect('${onSuspendedDay.single['description']}', contains('临时补课'));
  });

  test('ICS 文本正确转义中文特殊字符并按 75 字节折行', () {
    final base = buildTestTimetable(totalWeeks: 1);
    final longName = '算法,专题;路径\\实验\n第二行${List.filled(18, '超长课程名').join()}';
    final course = base.courses.first.copyWith(
      name: longName,
      note: '请携带资料,计算器;草稿纸',
    );
    final timetable = base.copyWith(
      courses: [course],
      sessions: [base.sessions.first],
    );

    final result = exportIcs(timetable, generatedAt: generatedAt);
    final unfolded = result.calendar.replaceAll(RegExp(r'\r\n[ \t]'), '');

    expect(result.calendar, contains('\r\n '));
    expect(unfolded, contains(r'SUMMARY:算法\,专题\;路径\\实验\n第二行'));
    expect(
      result.calendar
          .split('\r\n')
          .where((line) => line.isNotEmpty)
          .map((line) => utf8.encode(line).length),
      everyElement(lessThanOrEqualTo(75)),
    );
    expect(_events(result.calendar), hasLength(1));
  });

  test('ICS 导出结果可由 DeskTile 重新导入', () {
    final source = buildTestTimetable(totalWeeks: 2);
    final exported = exportIcs(source, generatedAt: generatedAt);
    final imported = importIcs(exported.calendar);

    expect(imported.termStart, testTermStart);
    expect(imported.totalWeeks, 2);
    expect(imported.courses.map((course) => course.name), contains('高等数学'));
    final math = imported.courses.singleWhere(
      (course) => course.name == '高等数学',
    );
    expect(math.weeks, [1, 2]);
    expect(math.position, '教三-305');
  });

  test('学期内没有实际课程时拒绝导出 ICS', () {
    final empty = buildTestTimetable(totalWeeks: 1)
        .copyWith(sessions: const []);
    expect(
      () => exportIcs(empty, generatedAt: generatedAt),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('没有实际课程'),
        ),
      ),
    );
  });
}

List<Map<String, dynamic>> _events(String calendar) =>
    ICalendar.fromString(calendar).data
        .where((item) => item['type'] == 'VEVENT')
        .toList();

DateTime _dateTime(Map<String, dynamic> event, String key) {
  final value = event[key] as IcsDateTime;
  return value.toDateTime()!;
}
