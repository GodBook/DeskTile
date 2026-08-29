import 'package:flutter_test/flutter_test.dart';

import 'package:desktile/core/widget_payload.dart';
import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:desktile/core/models/timetable.dart';

void main() {
  final timetable = Timetable(
    id: 't1',
    name: '测试课表',
    termStart: DateTime(2026, 8, 17),
    totalWeeks: 16,
    courses: const [Course(id: 'c1', name: '高等数学', teacher: '李老师')],
    sessions: [
      CourseSession(
        id: 's1',
        courseId: 'c1',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: {1},
        room: 'A-101',
      ),
    ],
  );

  test('从课表和考试生成紧凑 payload', () {
    final payload = buildWidgetPayload(
      timetable: timetable,
      exams: [
        Exam(
          id: 'e1',
          name: '英语考试',
          startAt: DateTime(2026, 8, 20, 9),
          room: 'B-202',
        ),
      ],
      now: DateTime(2026, 8, 17, 7),
    );

    expect(payload.week, 1);
    expect(payload.weekday, 1);
    expect(payload.weekdayLabel, '周一');
    expect(payload.nextTitle, '高等数学');
    expect(payload.nextRoom, 'A-101');
    expect(payload.nextTime, '08:00-09:35');
    expect(payload.nextIsCurrent, false);
    expect(payload.remainingToday, 1);
    expect(payload.examTitle, '英语考试');
    expect(payload.examAt, '08/20 09:00');
    expect(payload.examRoom, 'B-202');

    final decoded = WidgetPayload.fromJson(payload.encode());
    expect(decoded.toMap(), payload.toMap());
  });

  test('学期外日期返回空课程但仍可显示考试', () {
    final payload = buildWidgetPayload(
      timetable: timetable,
      now: DateTime(2027, 1, 1),
    );

    expect(payload.week, 0);
    expect(payload.weekday, 0);
    expect(payload.weekdayLabel, '学期外');
    expect(payload.nextTitle, isEmpty);
    expect(payload.remainingToday, 0);
  });

  test('停课后小组件不再显示该课程', () {
    final changed = timetable.copyWith(
      scheduleChanges: [
        ScheduleChange.cancellation(
          id: 'cancel',
          originalSessionId: 's1',
          originalDate: DateTime(2026, 8, 17),
        ),
      ],
    );
    final payload = buildWidgetPayload(
      timetable: changed,
      now: DateTime(2026, 8, 17, 7),
    );

    expect(payload.nextTitle, isEmpty);
    expect(payload.remainingToday, 0);
  });
}
