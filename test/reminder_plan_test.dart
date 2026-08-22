import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final t = buildTestTimetable();

  group('早八提醒（firstClassOfDay）', () {
    const settings = AppSettings(
      reminderMode: ReminderMode.firstClassOfDay,
      leadMinutes: 30,
    );

    test('每天只提醒第一节，且提前 30 分钟', () {
      final list = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 7, 0, 0),
        daysAhead: 1,
      );
      expect(list.length, 1);
      expect(list.first.fireAt, DateTime(2026, 9, 7, 7, 30));
      expect(list.first.title, '早八提醒：高等数学');
    });

    test('正文里一定有教室', () {
      final list = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 7),
        daysAhead: 1,
      );
      expect(list.first.body, contains('教三-305'));
      expect(list.first.body, contains('08:00 上课'));
      expect(list.first.body, contains('第1-2节'));
    });

    test('第一节课太晚（超过 09:00 阈值）就不提醒', () {
      // 周三第一节是第 6 节，14:00 开始
      final list = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 9),
        daysAhead: 1,
      );
      expect(list, isEmpty);
    });

    test('把阈值调到 24:00 就等于「每天第一节都提醒」', () {
      final list = buildReminders(
        timetable: t,
        settings: settings.copyWith(earlyClassCutoffMinutes: 24 * 60),
        from: DateTime(2026, 9, 9),
        daysAhead: 1,
      );
      expect(list.length, 1);
      expect(list.first.fireAt, DateTime(2026, 9, 9, 13, 30));
    });

    test('已经过去的时间点不再排', () {
      final list = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 7, 7, 45),
        daysAhead: 1,
      );
      expect(list, isEmpty);
    });

    test('单周课：第 2 周的周二没有提醒', () {
      final week1 = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 8),
        daysAhead: 1,
      );
      expect(week1.length, 1, reason: '第 1 周周二有线性代数');

      final week2 = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 15),
        daysAhead: 1,
      );
      expect(week2, isEmpty, reason: '第 2 周周二是双周，没有课');
    });

    test('一整周的提醒按时间升序', () {
      final list = buildReminders(
        timetable: t,
        settings: settings,
        from: DateTime(2026, 9, 7),
        daysAhead: 7,
      );
      // 周一、周二（单周）各一条；周三第一节太晚不提醒
      expect(list.length, 2);
      for (var i = 1; i < list.length; i++) {
        expect(list[i].fireAt.isAfter(list[i - 1].fireAt), isTrue);
      }
    });

    test('关掉提醒就什么都不排', () {
      final list = buildReminders(
        timetable: t,
        settings: settings.copyWith(reminderEnabled: false),
        from: DateTime(2026, 9, 7),
        daysAhead: 7,
      );
      expect(list, isEmpty);
    });
  });

  group('每节课提醒（everyClass）', () {
    test('周一两节课都排', () {
      final list = buildReminders(
        timetable: t,
        settings: const AppSettings(
          reminderMode: ReminderMode.everyClass,
          leadMinutes: 10,
        ),
        from: DateTime(2026, 9, 7),
        daysAhead: 1,
      );
      expect(list.length, 2);
      expect(list.map((r) => r.title), ['下节课：高等数学', '下节课：大学英语']);
      expect(list[1].fireAt, DateTime(2026, 9, 7, 9, 45));
    });
  });

  group('通知 id', () {
    test('同样的输入得到同样的 id', () {
      expect(reminderId(DateTime(2026, 9, 7), 's1'),
          reminderId(DateTime(2026, 9, 7), 's1'));
    });

    test('不同日期或不同时段得到不同 id', () {
      final a = reminderId(DateTime(2026, 9, 7), 's1');
      expect(a, isNot(reminderId(DateTime(2026, 9, 14), 's1')));
      expect(a, isNot(reminderId(DateTime(2026, 9, 7), 's2')));
    });

    test('id 落在 32 位正整数范围内', () {
      final id = reminderId(DateTime(2026, 9, 7), 's1');
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7fffffff));
    });
  });
}
