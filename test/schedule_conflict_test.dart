import 'package:desktile/core/models/academic_calendar_event.dart';
import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:desktile/core/models/time_slot.dart';
import 'package:desktile/core/schedule_conflict.dart';
import 'package:desktile/core/week_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('常规课程只在共同周次产生冲突，相邻时间不误报', () {
    final base = buildTestTimetable(totalWeeks: 3);
    final timetable = base.copyWith(
      courses: [
        ...base.courses,
        const Course(id: 'overlap', name: '大学物理'),
      ],
      sessions: [
        ...base.sessions,
        const CourseSession(
          id: 'overlap-session',
          courseId: 'overlap',
          day: 1,
          startSection: 1,
          endSection: 2,
          weeks: {1, 3},
        ),
      ],
    );

    final conflicts = detectScheduleConflicts(timetable);
    expect(conflicts, hasLength(2));
    expect(conflicts.map((item) => item.week), [1, 3]);
    expect(conflicts.first.sessions.map((item) => item.course.name).toSet(), {
      '高等数学',
      '大学物理',
    });
    expect(detectScheduleConflicts(base), isEmpty);
  });

  test('单次停课和校历批量停课会排除对应日期的冲突', () {
    final base = buildTestTimetable(totalWeeks: 3);
    final timetable = base.copyWith(
      courses: [
        ...base.courses,
        const Course(id: 'overlap', name: '大学物理'),
      ],
      sessions: [
        ...base.sessions,
        CourseSession(
          id: 'overlap-session',
          courseId: 'overlap',
          day: 1,
          startSection: 1,
          endSection: 2,
          weeks: allWeeks(3),
        ),
      ],
      scheduleChanges: [
        ScheduleChange.cancellation(
          id: 'cancel',
          originalSessionId: 'overlap-session',
          originalDate: DateTime(2026, 9, 7),
        ),
      ],
      academicCalendarEvents: [
        AcademicCalendarEvent(
          id: 'holiday',
          title: '校庆日',
          type: AcademicCalendarEventType.holiday,
          startDate: DateTime(2026, 9, 14),
          endDate: DateTime(2026, 9, 14),
        ),
      ],
    );

    final conflicts = detectScheduleConflicts(timetable);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.date, DateTime(2026, 9, 21));
    expect(conflicts.single.week, 3);
  });

  test('调课移除原安排，并在目标日期按实际时间参与检测', () {
    final base = buildTestTimetable(totalWeeks: 2);
    final timetable = base.copyWith(
      scheduleChanges: [
        ScheduleChange.reschedule(
          id: 'move',
          originalSessionId: 's1',
          originalDate: DateTime(2026, 9, 7),
          targetDate: DateTime(2026, 9, 8),
          startSection: 1,
          endSection: 2,
          room: '临时教室',
        ),
      ],
    );

    final conflicts = detectScheduleConflicts(timetable);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.date, DateTime(2026, 9, 8));
    expect(conflicts.single.sessions.map((item) => item.course.name).toSet(), {
      '高等数学',
      '线性代数',
    });
    expect(
      conflicts.single.sessions.any((item) => item.session.id == 'change:move'),
      isTrue,
    );
  });

  test('补课与多门课程重叠时合并为一处冲突', () {
    final base = buildTestTimetable(totalWeeks: 1);
    final timetable = base.copyWith(
      scheduleChanges: [
        ScheduleChange.extraClass(
          id: 'extra',
          courseId: 'c3',
          targetDate: DateTime(2026, 9, 7),
          startSection: 2,
          endSection: 3,
          room: '补课教室',
        ),
      ],
    );

    final conflicts = detectScheduleConflicts(timetable);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.sessions, hasLength(3));
    expect(conflicts.single.startMinutes, 8 * 60);
    expect(conflicts.single.endMinutes, 11 * 60 + 30);
  });

  test('不同节次的实际时刻交叠也会被识别', () {
    final base = buildTestTimetable(totalWeeks: 1);
    final slots = [
      for (final slot in base.timeSlots)
        if (slot.index == 3)
          const TimeSlot(
            index: 3,
            startMinutes: 9 * 60 + 30,
            endMinutes: 10 * 60 + 40,
          )
        else
          slot,
    ];

    final conflicts = detectScheduleConflicts(base.copyWith(timeSlots: slots));
    expect(conflicts, hasLength(1));
    expect(conflicts.single.sessions.map((item) => item.course.name).toSet(), {
      '高等数学',
      '大学英语',
    });
  });
}
