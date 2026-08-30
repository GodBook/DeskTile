import 'package:desktile/core/academic_calendar.dart';
import 'package:desktile/core/models/academic_calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('校历事件规范化日期并支持 JSON 往返', () {
    final event = AcademicCalendarEvent(
      id: 'holiday',
      title: '国庆假期',
      type: AcademicCalendarEventType.holiday,
      startDate: DateTime(2026, 10, 1, 12),
      endDate: DateTime(2026, 10, 7, 23),
    );

    expect(event.startDate, DateTime(2026, 10, 1));
    expect(event.endDate, DateTime(2026, 10, 7));
    expect(event.dayCount, 7);
    expect(event.contains(DateTime(2026, 10, 7, 18)), isTrue);
    expect(event.contains(DateTime(2026, 10, 8)), isFalse);

    final restored = AcademicCalendarEvent.fromJson(event.toJson());
    expect(restored.title, '国庆假期');
    expect(restored.type, AcademicCalendarEventType.holiday);
    expect(restored.suspendsClasses, isTrue);
  });

  test('批量停课统计常规课程并排除已有单次变更', () {
    final timetable = buildTestTimetable();
    final event = AcademicCalendarEvent(
      id: 'event',
      title: '开学活动',
      type: AcademicCalendarEventType.suspension,
      startDate: DateTime(2026, 9, 7),
      endDate: DateTime(2026, 9, 8),
    );

    expect(affectedRegularSessionCount(timetable, event), 3);
    expect(classSuspensionOnDate(timetable, DateTime(2026, 9, 7)), isNull);

    final withEvent = timetable.copyWith(academicCalendarEvents: [event]);
    expect(
      classSuspensionOnDate(withEvent, DateTime(2026, 9, 8))?.title,
      '开学活动',
    );
    expect(suspendedCalendarDayCount(withEvent), 2);
    expect(suspendedRegularSessionCount(withEvent), 3);
  });

  test('重叠停课区间按日期去重，纯标记不计入停课', () {
    final timetable = buildTestTimetable().copyWith(
      academicCalendarEvents: [
        AcademicCalendarEvent(
          id: 'first',
          title: '假期',
          type: AcademicCalendarEventType.holiday,
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 9),
        ),
        AcademicCalendarEvent(
          id: 'second',
          title: '统一停课',
          type: AcademicCalendarEventType.suspension,
          startDate: DateTime(2026, 9, 9),
          endDate: DateTime(2026, 9, 10),
        ),
        AcademicCalendarEvent(
          id: 'exam',
          title: '考试周',
          type: AcademicCalendarEventType.examWeek,
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 13),
          suspendsClasses: false,
        ),
      ],
    );

    expect(suspendedCalendarDayCount(timetable), 4);
    expect(calendarEventsOnDate(timetable, DateTime(2026, 9, 9)), hasLength(3));
  });
}
