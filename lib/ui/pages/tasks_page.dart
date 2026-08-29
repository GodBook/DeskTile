import 'package:flutter/material.dart';

import '../../core/models/course.dart';
import '../../core/models/task_item.dart';
import '../../core/models/timetable.dart';
import '../../core/task_query.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';
import '../theme.dart';

enum _TaskFilter { pending, completed, all }

enum _TaskMenuAction { edit, delete }

typedef _TaskCourse = ({Course course, Timetable timetable});

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  _TaskFilter _filter = _TaskFilter.pending;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = DateTime.now();
    final pendingCount = state.tasks.where((task) => !task.isCompleted).length;
    final nearest = nearestDueTask(state.tasks);
    final visible = sortedTasks(
      state.tasks.where((task) {
        return switch (_filter) {
          _TaskFilter.pending => !task.isCompleted,
          _TaskFilter.completed => task.isCompleted,
          _TaskFilter.all => true,
        };
      }),
      now,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '作业与待办',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => showTaskEditor(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加事项'),
              ),
            ],
          ),
        ),
        _TaskSummary(pendingCount: pendingCount, nearest: nearest, now: now),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_TaskFilter>(
              segments: const [
                ButtonSegment(
                  value: _TaskFilter.pending,
                  icon: Icon(Icons.radio_button_unchecked, size: 17),
                  label: Text('待完成'),
                ),
                ButtonSegment(
                  value: _TaskFilter.completed,
                  icon: Icon(Icons.task_alt, size: 17),
                  label: Text('已完成'),
                ),
                ButtonSegment(
                  value: _TaskFilter.all,
                  icon: Icon(Icons.list_alt, size: 17),
                  label: Text('全部'),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.single),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? _TaskEmptyState(
                  filter: _filter,
                  onAdd: () => showTaskEditor(context),
                )
              : _TaskList(tasks: visible, now: now),
        ),
      ],
    );
  }
}

class _TaskSummary extends StatelessWidget {
  const _TaskSummary({
    required this.pendingCount,
    required this.nearest,
    required this.now,
  });

  final int pendingCount;
  final TaskItem? nearest;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueAt = nearest?.dueAt;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            pendingCount == 0 ? Icons.done_all : Icons.pending_actions,
            color: pendingCount == 0
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  pendingCount == 0 ? '暂无待完成事项' : '$pendingCount 项待完成',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dueAt != null)
                  Text(
                    '最近截止：${_dueText(dueAt, now)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: dueAt.isBefore(now)
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskEmptyState extends StatelessWidget {
  const _TaskEmptyState({required this.filter, required this.onAdd});

  final _TaskFilter filter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (filter) {
      _TaskFilter.pending => (Icons.done_all, '没有待完成事项'),
      _TaskFilter.completed => (Icons.history_toggle_off, '还没有已完成事项'),
      _TaskFilter.all => (Icons.assignment_outlined, '还没有作业或待办'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Text(label),
          if (filter != _TaskFilter.completed) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加事项'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.now});

  final List<TaskItem> tasks;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final grouped = <TaskGroup, List<TaskItem>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(taskGroupOf(task, now), () => []).add(task);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final group in TaskGroup.values)
          if (grouped[group] case final items?) ...[
            _TaskGroupHeader(group: group, count: items.length),
            for (final task in items) ...[
              _TaskRow(task: task, now: now),
              const Divider(height: 1),
            ],
          ],
      ],
    );
  }
}

class _TaskGroupHeader extends StatelessWidget {
  const _TaskGroupHeader({required this.group, required this.count});

  final TaskGroup group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (group) {
      TaskGroup.overdue => '逾期',
      TaskGroup.today => '今天',
      TaskGroup.upcoming => '接下来',
      TaskGroup.noDeadline => '无截止日期',
      TaskGroup.completed => '已完成',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 5),
      child: Text(
        '$label  $count',
        style: theme.textTheme.labelLarge?.copyWith(
          color: group == TaskGroup.overdue
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.now});

  final TaskItem task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final linked = _taskCourse(state, task);
    final linkedColor = linked == null
        ? null
        : courseColor(linked.course.colorSeed, theme.brightness);
    final group = taskGroupOf(task, now);
    final dueColor = switch (group) {
      TaskGroup.overdue => theme.colorScheme.error,
      TaskGroup.today => theme.colorScheme.primary,
      _ => theme.colorScheme.outline,
    };

    return Material(
      key: ValueKey('task-row-${task.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showTaskEditor(context, task: task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                key: ValueKey('task-checkbox-${task.id}'),
                value: task.isCompleted,
                onChanged: (value) =>
                    AppScope.read(context)
                        .setTaskCompleted(task.id, value ?? false),
              ),
              if (linkedColor != null) ...[
                Container(width: 3, height: 38, color: linkedColor),
                const SizedBox(width: 10),
              ] else
                const SizedBox(width: 6),
              Expanded(
                child: Opacity(
                  opacity: task.isCompleted ? 0.58 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (task.priority == TaskPriority.important)
                            Tooltip(
                              message: '重要',
                              child: Icon(
                                Icons.flag_rounded,
                                size: 17,
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: [
                          _TaskMeta(
                            icon: task.kind == TaskKind.homework
                                ? Icons.menu_book_outlined
                                : Icons.checklist,
                            label: task.kind == TaskKind.homework ? '作业' : '待办',
                          ),
                          if (linked != null)
                            _TaskMeta(
                              icon: Icons.school_outlined,
                              label: linked.course.name,
                              color: linkedColor,
                            ),
                          if (task.dueAt != null)
                            _TaskMeta(
                              icon: Icons.schedule,
                              label: _dueText(task.dueAt!, now),
                              color: dueColor,
                            ),
                        ],
                      ),
                      if (task.note?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_TaskMenuAction>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) {
                  switch (action) {
                    case _TaskMenuAction.edit:
                      showTaskEditor(context, task: task);
                    case _TaskMenuAction.delete:
                      AppScope.read(context).deleteTask(task.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _TaskMenuAction.edit,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _TaskMenuAction.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 10),
                        Text('删除'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: foreground),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: foreground),
        ),
      ],
    );
  }
}

Future<void> showTaskEditor(BuildContext context, {TaskItem? task}) async {
  final state = AppScope.read(context);
  Timetable? timetable;
  final targetTimetableId = task?.timetableId ?? state.activeTimetable?.id;
  for (final candidate in state.data.timetables) {
    if (candidate.id == targetTimetableId) {
      timetable = candidate;
      break;
    }
  }
  timetable ??= state.activeTimetable;
  await showDialog<void>(
    context: context,
    builder: (context) => _TaskEditorDialog(task: task, timetable: timetable),
  );
}

class _TaskEditorDialog extends StatefulWidget {
  const _TaskEditorDialog({required this.task, required this.timetable});

  final TaskItem? task;
  final Timetable? timetable;

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  late TaskKind _kind;
  late TaskPriority _priority;
  late String _courseId;
  late bool _hasDeadline;
  late DateTime _dueDate;
  late TimeOfDay _dueTime;
  late final TextEditingController _title;
  late final TextEditingController _note;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final now = DateTime.now();
    final fallbackDue = DateTime(now.year, now.month, now.day + 1, 23, 59);
    final dueAt = task?.dueAt ?? fallbackDue;
    _kind = task?.kind ?? TaskKind.homework;
    _priority = task?.priority ?? TaskPriority.normal;
    _courseId = task?.courseId ?? '';
    if (_courseId.isNotEmpty &&
        !(widget.timetable?.courses.any((course) => course.id == _courseId) ??
            false)) {
      _courseId = '';
    }
    _hasDeadline = task?.dueAt != null || task == null;
    _dueDate = DateTime(dueAt.year, dueAt.month, dueAt.day);
    _dueTime = TimeOfDay(hour: dueAt.hour, minute: dueAt.minute);
    _title = TextEditingController(text: task?.title ?? '');
    _note = TextEditingController(text: task?.note ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _combinedDue => DateTime(
    _dueDate.year,
    _dueDate.month,
    _dueDate.day,
    _dueTime.hour,
    _dueTime.minute,
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(_dueDate.year - 2),
      lastDate: DateTime(_dueDate.year + 10),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请输入标题');
      return;
    }
    final courseId = _courseId.isEmpty ? null : _courseId;
    final existing = widget.task;
    final task = TaskItem(
      id: existing?.id ?? newId('task'),
      title: title,
      kind: _kind,
      createdAt: existing?.createdAt ?? DateTime.now(),
      dueAt: _hasDeadline ? _combinedDue : null,
      timetableId: courseId == null ? null : widget.timetable?.id,
      courseId: courseId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      priority: _priority,
      completedAt: existing?.completedAt,
    );
    await AppScope.read(context).putTask(task);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await AppScope.read(context).deleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final courses = widget.timetable?.courses ?? const <Course>[];
    return AlertDialog(
      title: Text(widget.task == null ? '添加事项' : '编辑事项'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.maxFinite : 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TaskKind>(
                segments: const [
                  ButtonSegment(
                    value: TaskKind.homework,
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                    label: Text('作业'),
                  ),
                  ButtonSegment(
                    value: TaskKind.todo,
                    icon: Icon(Icons.checklist, size: 18),
                    label: Text('待办'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.single),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('task-title'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '标题 *',
                  errorText: _titleError,
                ),
                onChanged: (_) {
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
              if (courses.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('task-course'),
                  initialValue: _courseId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '关联课程'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不关联课程')),
                    for (final course in courses)
                      DropdownMenuItem(
                        value: course.id,
                        child: Text(
                          course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _courseId = value ?? ''),
                ),
              ],
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('标为重要'),
                value: _priority == TaskPriority.important,
                onChanged: (value) => setState(
                  () => _priority = value ?? false
                      ? TaskPriority.important
                      : TaskPriority.normal,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设置截止时间'),
                value: _hasDeadline,
                onChanged: (value) => setState(() => _hasDeadline = value),
              ),
              if (_hasDeadline) ...[
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final dateButton = OutlinedButton.icon(
                      key: const ValueKey('task-due-date'),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(monthDayText(_dueDate)),
                    );
                    final timeButton = OutlinedButton.icon(
                      key: const ValueKey('task-due-time'),
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(_timeText(_dueTime)),
                    );
                    if (constraints.maxWidth < 320) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          dateButton,
                          const SizedBox(height: 10),
                          timeButton,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: dateButton),
                        const SizedBox(width: 12),
                        Expanded(child: timeButton),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: '备注'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.task != null)
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

_TaskCourse? _taskCourse(AppState state, TaskItem task) {
  Timetable? timetable;
  for (final candidate in state.data.timetables) {
    if (candidate.id == task.timetableId) {
      timetable = candidate;
      break;
    }
  }
  timetable ??= state.activeTimetable;
  final course = timetable?.courseById(task.courseId ?? '');
  return timetable == null || course == null
      ? null
      : (course: course, timetable: timetable);
}

String _dueText(DateTime dueAt, DateTime now) {
  final time =
      '${dueAt.hour.toString().padLeft(2, '0')}:'
      '${dueAt.minute.toString().padLeft(2, '0')}';
  final sameDay =
      dueAt.year == now.year &&
      dueAt.month == now.month &&
      dueAt.day == now.day;
  if (sameDay) {
    return dueAt.isBefore(now) ? '今天 $time 已逾期' : '今天 $time';
  }
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  if (dueAt.year == tomorrow.year &&
      dueAt.month == tomorrow.month &&
      dueAt.day == tomorrow.day) {
    return '明天 $time';
  }
  return '${dueAt.month}月${dueAt.day}日 $time';
}

String _timeText(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
