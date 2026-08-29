import 'package:desktile/core/models/task_item.dart';
import 'package:desktile/core/task_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 10, 12);

  TaskItem task({
    required String id,
    DateTime? dueAt,
    TaskPriority priority = TaskPriority.normal,
    DateTime? completedAt,
    DateTime? createdAt,
  }) => TaskItem(
    id: id,
    title: id,
    kind: TaskKind.todo,
    createdAt: createdAt ?? DateTime(2026, 9, 1),
    dueAt: dueAt,
    priority: priority,
    completedAt: completedAt,
  );

  test('作业字段 JSON 往返完整保留', () {
    final original = TaskItem(
      id: 'task1',
      title: '完成高数习题',
      kind: TaskKind.homework,
      createdAt: DateTime(2026, 9, 8, 9),
      dueAt: DateTime(2026, 9, 10, 23, 59),
      timetableId: 't1',
      courseId: 'c1',
      note: '第 1-12 题',
      priority: TaskPriority.important,
      completedAt: DateTime(2026, 9, 10, 20),
    );

    final restored = TaskItem.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.kind, TaskKind.homework);
    expect(restored.dueAt, original.dueAt);
    expect(restored.timetableId, 't1');
    expect(restored.courseId, 'c1');
    expect(restored.note, '第 1-12 题');
    expect(restored.priority, TaskPriority.important);
    expect(restored.completedAt, original.completedAt);
  });

  test('完成与恢复不改变事项本身', () {
    final original = task(id: 'task1', dueAt: DateTime(2026, 9, 11));
    final completedAt = DateTime(2026, 9, 10, 13);

    final completed = original.withCompletion(true, at: completedAt);
    final restored = completed.withCompletion(false);

    expect(completed.completedAt, completedAt);
    expect(restored.isCompleted, isFalse);
    expect(restored.title, original.title);
    expect(restored.dueAt, original.dueAt);
  });

  test('事项按逾期、今天、接下来、无截止、已完成分组', () {
    expect(
      taskGroupOf(
        task(id: '逾期', dueAt: now.subtract(const Duration(hours: 1))),
        now,
      ),
      TaskGroup.overdue,
    );
    expect(
      taskGroupOf(
        task(id: '今天', dueAt: now.add(const Duration(hours: 1))),
        now,
      ),
      TaskGroup.today,
    );
    expect(
      taskGroupOf(
        task(id: '接下来', dueAt: now.add(const Duration(days: 1))),
        now,
      ),
      TaskGroup.upcoming,
    );
    expect(taskGroupOf(task(id: '无截止'), now), TaskGroup.noDeadline);
    expect(
      taskGroupOf(task(id: '完成', completedAt: now), now),
      TaskGroup.completed,
    );
  });

  test('未完成事项按分组和截止时间排序，无截止时重要项优先', () {
    final result = sortedTasks([
      task(id: '普通无截止'),
      task(id: '明天晚', dueAt: DateTime(2026, 9, 11, 20)),
      task(id: '重要无截止', priority: TaskPriority.important),
      task(id: '今天', dueAt: DateTime(2026, 9, 10, 18)),
      task(id: '逾期', dueAt: DateTime(2026, 9, 9, 18)),
      task(id: '明天早', dueAt: DateTime(2026, 9, 11, 8)),
    ], now);

    expect(result.map((item) => item.id), [
      '逾期',
      '今天',
      '明天早',
      '明天晚',
      '重要无截止',
      '普通无截止',
    ]);
  });

  test('已完成事项按完成时间倒序', () {
    final result = sortedTasks([
      task(id: '早完成', completedAt: DateTime(2026, 9, 9)),
      task(id: '晚完成', completedAt: DateTime(2026, 9, 10)),
    ], now);

    expect(result.map((item) => item.id), ['晚完成', '早完成']);
  });

  test('最近截止忽略已完成和无截止事项', () {
    final nearest = nearestDueTask([
      task(id: '无截止'),
      task(id: '已完成', dueAt: DateTime(2026, 9, 8), completedAt: now),
      task(id: '较晚', dueAt: DateTime(2026, 9, 12)),
      task(id: '最近', dueAt: DateTime(2026, 9, 11)),
    ]);

    expect(nearest?.id, '最近');
  });
}
