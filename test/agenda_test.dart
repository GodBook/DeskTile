import 'package:desktile/core/agenda.dart';
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
      expect(list.first.session.startOn(list.first.date), DateTime(2026, 9, 7, 8));
    });

    test('学期外返回空', () {
      expect(agendaForDate(t, DateTime(2026, 9, 1)), isEmpty);
      expect(agendaForDate(t, DateTime(2027, 6, 1)), isEmpty);
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
      expect(nextSession(t, DateTime(2026, 9, 7, 9, 45))?.session.course.name, '大学英语');
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
