import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/models/task_item.dart';
import 'package:desktile/core/reminder_plan.dart';
import 'package:desktile/core/task_reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final timetable = buildTestTimetable();
  final now = DateTime(2026, 9, 7, 8);

  TaskItem task({
    required String id,
    DateTime? reminderAt,
    DateTime? dueAt,
    DateTime? completedAt,
    String? timetableId,
    String? courseId,
  }) => TaskItem(
    id: id,
    title: id,
    kind: TaskKind.homework,
    createdAt: DateTime(2026, 9, 1),
    reminderAt: reminderAt,
    dueAt: dueAt,
    completedAt: completedAt,
    timetableId: timetableId,
    courseId: courseId,
  );

  test('只调度未完成且提醒时间仍在未来的事项', () {
    final reminders = buildTaskReminders(
      tasks: [
        task(id: '未来', reminderAt: DateTime(2026, 9, 7, 10)),
        task(id: '无提醒'),
        task(id: '已过去', reminderAt: DateTime(2026, 9, 7, 7)),
        task(
          id: '已完成',
          reminderAt: DateTime(2026, 9, 7, 11),
          completedAt: DateTime(2026, 9, 7, 7, 30),
        ),
      ],
      timetables: [timetable],
      settings: const AppSettings(),
      from: now,
    );

    expect(reminders.map((item) => item.taskId), ['未来']);
  });

  test('正文包含关联课程与截止时间', () {
    final reminders = buildTaskReminders(
      tasks: [
        task(
          id: '高数作业',
          reminderAt: DateTime(2026, 9, 7, 10),
          dueAt: DateTime(2026, 9, 8, 23, 59),
          timetableId: timetable.id,
          courseId: 'c1',
        ),
      ],
      timetables: [timetable],
      settings: const AppSettings(),
      from: now,
    );

    expect(reminders.single.title, '作业提醒：高数作业');
    expect(reminders.single.body, contains('高等数学'));
    expect(reminders.single.body, contains('截止 9月8日 23:59'));
  });

  test('提醒按触发时间升序', () {
    final reminders = buildTaskReminders(
      tasks: [
        task(id: '晚', reminderAt: DateTime(2026, 9, 7, 12)),
        task(id: '早', reminderAt: DateTime(2026, 9, 7, 9)),
      ],
      timetables: [timetable],
      settings: const AppSettings(),
      from: now,
    );

    expect(reminders.map((item) => item.taskId), ['早', '晚']);
  });

  test('关闭作业与待办提醒后不调度', () {
    final reminders = buildTaskReminders(
      tasks: [task(id: '未来', reminderAt: DateTime(2026, 9, 7, 10))],
      timetables: [timetable],
      settings: const AppSettings(taskReminderEnabled: false),
      from: now,
    );

    expect(reminders, isEmpty);
  });

  test('待办通知与课程通知使用不同 id 命名空间', () {
    final courseId = reminderId(DateTime(2026, 9, 7), 's1');
    final taskId = taskReminderId('task1');

    expect(courseId, lessThan(0x40000000));
    expect(taskId, greaterThanOrEqualTo(0x40000000));
    expect(taskId, lessThanOrEqualTo(0x7fffffff));
    expect(taskId, isNot(courseId));
  });
}
