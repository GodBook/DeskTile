import 'models/task_item.dart';

enum TaskGroup { overdue, today, upcoming, noDeadline, completed }

TaskGroup taskGroupOf(TaskItem task, DateTime now) {
  if (task.isCompleted) return TaskGroup.completed;
  final dueAt = task.dueAt;
  if (dueAt == null) return TaskGroup.noDeadline;
  if (dueAt.isBefore(now)) return TaskGroup.overdue;
  if (_sameDate(dueAt, now)) return TaskGroup.today;
  return TaskGroup.upcoming;
}

List<TaskItem> sortedTasks(Iterable<TaskItem> tasks, DateTime now) {
  final result = tasks.toList();
  result.sort((left, right) {
    final leftGroup = taskGroupOf(left, now);
    final rightGroup = taskGroupOf(right, now);
    final groupOrder = leftGroup.index.compareTo(rightGroup.index);
    if (groupOrder != 0) return groupOrder;

    if (leftGroup == TaskGroup.completed) {
      return (right.completedAt ?? right.createdAt).compareTo(
        left.completedAt ?? left.createdAt,
      );
    }

    final leftDue = left.dueAt;
    final rightDue = right.dueAt;
    if (leftDue != null && rightDue != null) {
      final dueOrder = leftDue.compareTo(rightDue);
      if (dueOrder != 0) return dueOrder;
    } else if (leftDue != null) {
      return -1;
    } else if (rightDue != null) {
      return 1;
    }

    final priorityOrder = right.priority.index.compareTo(left.priority.index);
    if (priorityOrder != 0) return priorityOrder;
    return left.createdAt.compareTo(right.createdAt);
  });
  return result;
}

TaskItem? nearestDueTask(Iterable<TaskItem> tasks) {
  TaskItem? nearest;
  for (final task in tasks) {
    if (task.isCompleted || task.dueAt == null) continue;
    if (nearest == null || task.dueAt!.isBefore(nearest.dueAt!)) {
      nearest = task;
    }
  }
  return nearest;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
