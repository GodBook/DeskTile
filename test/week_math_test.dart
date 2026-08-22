import 'package:desktile/core/models/timetable.dart';
import 'package:desktile/core/week_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('currentWeek', () {
    test('学期第一天是第 1 周', () {
      expect(currentWeek(testTermStart, DateTime(2026, 9, 7, 8), 16), 1);
    });

    test('第一周的周日仍是第 1 周', () {
      expect(currentWeek(testTermStart, DateTime(2026, 9, 13, 23, 59), 16), 1);
    });

    test('第八天进入第 2 周', () {
      expect(currentWeek(testTermStart, DateTime(2026, 9, 14), 16), 2);
    });

    test('学期开始前返回 null', () {
      expect(currentWeek(testTermStart, DateTime(2026, 9, 6, 23), 16), isNull);
    });

    test('超过总周数返回 null', () {
      // 第 17 周的周一
      expect(currentWeek(testTermStart, DateTime(2026, 12, 28), 16), isNull);
    });

    test('clampedWeek 在学期外也给出可用的周次', () {
      expect(clampedWeek(testTermStart, DateTime(2026, 8, 1), 16), 1);
      expect(clampedWeek(testTermStart, DateTime(2027, 3, 1), 16), 16);
    });
  });

  group('日期换算', () {
    test('dateOfWeekDay', () {
      expect(dateOfWeekDay(testTermStart, 1, 1), DateTime(2026, 9, 7));
      expect(dateOfWeekDay(testTermStart, 3, 5), DateTime(2026, 9, 25));
    });

    test('weekDayOfDate 与 dateOfWeekDay 互逆', () {
      for (final week in [1, 2, 7, 16]) {
        for (final day in [1, 4, 7]) {
          final date = dateOfWeekDay(testTermStart, week, day);
          final back = weekDayOfDate(testTermStart, date, 16);
          expect(back, isNotNull);
          expect(back!.week, week);
          expect(back.day, day);
        }
      }
    });

    test('mondayOf', () {
      expect(mondayOf(DateTime(2026, 9, 25)), DateTime(2026, 9, 21));
      expect(mondayOf(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
      expect(mondayOf(DateTime(2026, 9, 27)), DateTime(2026, 9, 21));
    });

    test('daysBetween 不受一天内的时刻影响', () {
      expect(daysBetween(DateTime(2026, 9, 7, 23), DateTime(2026, 9, 8, 1)), 1);
    });
  });

  group('单双周集合', () {
    test('oddWeeks / evenWeeks / allWeeks', () {
      expect(oddWeeks(6), {1, 3, 5});
      expect(evenWeeks(6), {2, 4, 6});
      expect(allWeeks(6), {1, 2, 3, 4, 5, 6});
    });
  });

  test('Timetable 会把学期开始日对齐到周一', () {
    // 2026-09-09 是周三
    final t = Timetable(id: 'x', name: 'x', termStart: DateTime(2026, 9, 9));
    expect(t.termStart, DateTime(2026, 9, 7));
  });
}
