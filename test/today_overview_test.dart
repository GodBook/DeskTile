import 'package:desktile/core/agenda.dart';
import 'package:desktile/core/models/academic_calendar_event.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:desktile/core/models/task_item.dart';
import 'package:desktile/core/today_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2026, 9, 7, 12);

  TaskItem task({required String id, DateTime? dueAt, DateTime? completedAt}) =>
      TaskItem(
        id: id,
        title: id,
        kind: TaskKind.todo,
        createdAt: DateTime(2026, 9, 1),
        dueAt: dueAt,
        completedAt: completedAt,
      );

  Exam exam(String id, DateTime startAt) =>
      Exam(id: id, name: id, startAt: startAt);

  test('今天课程同时展示停课、调出来源和临时补课', () {
    final timetable = buildTestTimetable().copyWith(
      scheduleChanges: [
        ScheduleChange.cancellation(
          id: 'cancel',
          originalSessionId: 's1',
          originalDate: now,
        ),
        ScheduleChange.reschedule(
          id: 'move',
          originalSessionId: 's2',
          originalDate: now,
          targetDate: now.add(const Duration(days: 1)),
          startSection: 5,
          endSection: 6,
        ),
        ScheduleChange.extraClass(
          id: 'extra',
          courseId: 'c3',
          targetDate: now,
          startSection: 8,
          endSection: 9,
        ),
      ],
    );

    final overview = buildTodayOverview(
      timetable: timetable,
      tasks: const [],
      exams: const [],
      now: now,
    );

    expect(overview.sessions.map((item) => item.occurrence), [
      SessionOccurrenceKind.cancelled,
      SessionOccurrenceKind.rescheduledSource,
      SessionOccurrenceKind.extraClass,
    ]);
  });

  test('截止事项包含今天和逾期，排除明天及已完成事项', () {
    final overview = buildTodayOverview(
      timetable: null,
      tasks: [
        task(id: '逾期', dueAt: DateTime(2026, 9, 6, 18)),
        task(id: '今天', dueAt: DateTime(2026, 9, 7, 23)),
        task(id: '明天', dueAt: DateTime(2026, 9, 8, 8)),
        task(
          id: '已完成',
          dueAt: DateTime(2026, 9, 7, 20),
          completedAt: DateTime(2026, 9, 7, 10),
        ),
        task(id: '无截止'),
      ],
      exams: const [],
      now: now,
    );

    expect(overview.dueTasks.map((item) => item.id), ['逾期', '今天']);
  });

  test('今天页保留校历停课来源供用户识别', () {
    final timetable = buildTestTimetable().copyWith(
      academicCalendarEvents: [
        AcademicCalendarEvent(
          id: 'holiday',
          title: '校庆日',
          type: AcademicCalendarEventType.holiday,
          startDate: now,
          endDate: now,
        ),
      ],
    );

    final overview = buildTodayOverview(
      timetable: timetable,
      tasks: const [],
      exams: const [],
      now: now,
    );

    expect(overview.sessions, hasLength(2));
    expect(
      overview.sessions.map((item) => item.occurrence),
      everyElement(SessionOccurrenceKind.calendarSuspended),
    );
    expect(overview.sessions.first.calendarEvent?.title, '校庆日');
  });

  test('近期考试按时间排序并限制为三场', () {
    final overview = buildTodayOverview(
      timetable: null,
      tasks: const [],
      exams: [
        exam('第四场', DateTime(2026, 9, 11)),
        exam('第二场', DateTime(2026, 9, 9)),
        exam('已结束', DateTime(2026, 9, 1)),
        exam('第一场', DateTime(2026, 9, 8)),
        exam('第三场', DateTime(2026, 9, 10)),
      ],
      now: now,
    );

    expect(overview.upcomingExams.map((item) => item.exam.id), [
      '第一场',
      '第二场',
      '第三场',
    ]);
  });
}
