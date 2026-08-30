import 'models/settings.dart';
import 'models/task_item.dart';
import 'models/timetable.dart';
import 'stable_hash.dart';

class PlannedTaskReminder {
  const PlannedTaskReminder({
    required this.id,
    required this.taskId,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final int id;
  final String taskId;
  final DateTime fireAt;
  final String title;
  final String body;
}

List<PlannedTaskReminder> buildTaskReminders({
  required Iterable<TaskItem> tasks,
  required Iterable<Timetable> timetables,
  required AppSettings settings,
  required DateTime from,
}) {
  if (!settings.taskReminderEnabled) return const [];
  final tables = {for (final timetable in timetables) timetable.id: timetable};
  final result = <PlannedTaskReminder>[];
  for (final task in tasks) {
    final fireAt = task.reminderAt;
    if (task.isCompleted || fireAt == null || !fireAt.isAfter(from)) continue;
    final timetable = tables[task.timetableId];
    final course = timetable?.courseById(task.courseId ?? '');
    final parts = <String>[];
    if (course != null) parts.add(course.name);
    if (task.dueAt case final dueAt?) {
      parts.add('截止 ${_dateTimeText(dueAt)}');
    } else {
      parts.add('记得按时完成');
    }
    result.add(
      PlannedTaskReminder(
        id: taskReminderId(task.id),
        taskId: task.id,
        fireAt: fireAt,
        title:
            '${task.kind == TaskKind.homework ? '作业' : '待办'}提醒：${task.title}',
        body: parts.join(' · '),
      ),
    );
  }
  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return result;
}

int taskReminderId(String taskId) =>
    (stableHash('task|$taskId') & 0x3fffffff) | 0x40000000;

String _dateTimeText(DateTime value) =>
    '${value.month}月${value.day}日 '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
