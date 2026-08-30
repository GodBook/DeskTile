import 'package:desktile/core/agenda.dart';
import 'package:desktile/core/models/academic_calendar_event.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final t = buildTestTimetable();

  group('sessionsOnWeekDay', () {
    test('周一两节课，按节次排序', () {
      final list = sessionsOnWeekDay(t, 1, 1);
      expect(list.map((s) => s.course.name), ['高等数学', '大学英语']);
      expect(list.first.startSlot.startText, '08:00');
      expect(list.first.endSlot.endText, '09:35');
    });

    test('单周课只在奇数周出现', () {
      expect(sessionsOnWeekDay(t, 1, 2).map((s) => s.course.name), ['线性代数']);
      expect(sessionsOnWeekDay(t, 2, 2), isEmpty);
      expect(sessionsOnWeekDay(t, 3, 2).map((s) => s.course.name), ['线性代数']);
    });

    test('没课的日子返回空', () {
      expect(sessionsOnWeekDay(t, 1, 6), isEmpty);
    });

    test('节次文案', () {
      expect(sessionsOnWeekDay(t, 1, 1).first.sectionText, '第1-2节');
      expect(sessionsOnWeekDay(t, 1, 1).first.timeText, '08:00-09:35');
    });
  });

  group('agendaForDate', () {
    test('第 1 周周一', () {
      final list = agendaForDate(t, DateTime(2026, 9, 7));
      expect(list.length, 2);
      expect(
        list.first.session.startOn(list.first.date),
        DateTime(2026, 9, 7, 8),
      );
    });

    test('学期外返回空', () {
      expect(agendaForDate(t, DateTime(2026, 9, 1)), isEmpty);
      expect(agendaForDate(t, DateTime(2027, 6, 1)), isEmpty);
    });
  });

  group('临时课程变更', () {
    test('停课从实际日程移除，但周视图仍能显示停课来源', () {
      final changed = t.copyWith(
        scheduleChanges: [
          ScheduleChange.cancellation(
            id: 'change1',
            originalSessionId: 's1',
            originalDate: DateTime(2026, 9, 7),
          ),
        ],
      );

      expect(
        agendaForDate(
          changed,
          DateTime(2026, 9, 7),
        ).map((item) => item.session.course.name),
        ['大学英语'],
      );
      final visual = sessionsOnWeekDay(
        changed,
        1,
        1,
        includeChangedSources: true,
      );
      expect(visual.length, 2);
      expect(visual.first.occurrence, SessionOccurrenceKind.cancelled);
      expect(visual.first.isInactive, isTrue);
    });

    test('调课从原日期移除并在目标日期按新节次和教室出现', () {
      final changed = t.copyWith(
        scheduleChanges: [
          ScheduleChange.reschedule(
            id: 'change2',
            originalSessionId: 's1',
            originalDate: DateTime(2026, 9, 7),
            targetDate: DateTime(2026, 9, 8),
            startSection: 3,
            endSection: 4,
            room: '临时教室',
          ),
        ],
      );

      expect(
        agendaForDate(
          changed,
          DateTime(2026, 9, 7),
        ).map((item) => item.session.course.name),
        ['大学英语'],
      );
      final target = agendaForDate(changed, DateTime(2026, 9, 8));
      expect(target.map((item) => item.session.course.name), ['线性代数', '高等数学']);
      expect(
        target.last.session.occurrence,
        SessionOccurrenceKind.rescheduledTarget,
      );
      expect(target.last.session.session.startSection, 3);
      expect(target.last.session.session.room, '临时教室');
    });

    test('补课作为一次性课程加入目标日期', () {
      final changed = t.copyWith(
        scheduleChanges: [
          ScheduleChange.extraClass(
            id: 'change3',
            courseId: 'c2',
            targetDate: DateTime(2026, 9, 10),
            startSection: 5,
            endSection: 6,
            room: '补课教室',
          ),
        ],
      );

      final target = agendaForDate(changed, DateTime(2026, 9, 10));
      expect(target.single.session.course.name, '大学英语');
      expect(
        target.single.session.occurrence,
        SessionOccurrenceKind.extraClass,
      );
      expect(target.single.session.session.id, 'change:change3');
    });
  });

  group('学期校历', () {
    test('批量停课从实际日程移除，周视图保留校历停课来源', () {
      final event = AcademicCalendarEvent(
        id: 'holiday',
        title: '校庆日',
        type: AcademicCalendarEventType.holiday,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 8),
      );
      final changed = t.copyWith(academicCalendarEvents: [event]);

      expect(agendaForDate(changed, DateTime(2026, 9, 7)), isEmpty);
      final visual = sessionsOnDate(
        changed,
        DateTime(2026, 9, 7),
        includeChangedSources: true,
      );
      expect(visual, hasLength(2));
      expect(
        visual.map((item) => item.occurrence),
        everyElement(SessionOccurrenceKind.calendarSuspended),
      );
      expect(visual.first.calendarEvent?.title, '校庆日');
    });

    test('纯校历标记不暂停课程', () {
      final changed = t.copyWith(
        academicCalendarEvents: [
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

      expect(agendaForDate(changed, DateTime(2026, 9, 7)), hasLength(2));
    });

    test('校历停课不覆盖显式添加的补课', () {
      final changed = t.copyWith(
        academicCalendarEvents: [
          AcademicCalendarEvent(
            id: 'holiday',
            title: '假期',
            type: AcademicCalendarEventType.holiday,
            startDate: DateTime(2026, 9, 7),
            endDate: DateTime(2026, 9, 7),
          ),
        ],
        scheduleChanges: [
          ScheduleChange.extraClass(
            id: 'extra',
            courseId: 'c3',
            targetDate: DateTime(2026, 9, 7),
            startSection: 8,
            endSection: 9,
          ),
        ],
      );

      final actual = agendaForDate(changed, DateTime(2026, 9, 7));
      expect(actual, hasLength(1));
      expect(
        actual.single.session.occurrence,
        SessionOccurrenceKind.extraClass,
      );
    });
  });

  group('nextSession / currentSession / remainingToday', () {
    test('上课前，下一节是当天第一节', () {
      final next = nextSession(t, DateTime(2026, 9, 7, 7, 0));
      expect(next, isNotNull);
      expect(next!.session.course.name, '高等数学');
    });

    test('第一节上课中：currentSession 有值，nextSession 是下一节', () {
      final now = DateTime(2026, 9, 7, 8, 20);
      expect(currentSession(t, now)?.session.course.name, '高等数学');
      expect(nextSession(t, now)?.session.course.name, '大学英语');
    });

    test('课间：没有正在上的课', () {
      // 09:35 下课，09:55 上课
      expect(currentSession(t, DateTime(2026, 9, 7, 9, 45)), isNull);
      expect(
        nextSession(t, DateTime(2026, 9, 7, 9, 45))?.session.course.name,
        '大学英语',
      );
    });

    test('当天课全上完后跨天找下一节', () {
      final next = nextSession(t, DateTime(2026, 9, 7, 20, 0));
      expect(next, isNotNull);
      expect(next!.session.course.name, '线性代数');
      expect(next.date, DateTime(2026, 9, 8));
    });

    test('remainingToday 只看今天', () {
      expect(remainingToday(t, DateTime(2026, 9, 7, 7)).length, 2);
      expect(remainingToday(t, DateTime(2026, 9, 7, 10)).length, 1);
      expect(remainingToday(t, DateTime(2026, 9, 7, 20)), isEmpty);
    });

    test('学期结束后没有下一节', () {
      expect(nextSession(t, DateTime(2027, 1, 1)), isNull);
    });
  });
}
