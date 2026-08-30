import 'package:flutter/material.dart';

import '../../core/models/timetable.dart';
import '../../core/models/time_slot.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';
import '../theme.dart';

Future<void> showTimetableManager(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _TimetableManagerDialog(),
);

class _TimetableManagerDialog extends StatelessWidget {
  const _TimetableManagerDialog();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final activeId = state.activeTimetable?.id;
    final current = state.timetables.where((t) => !t.archived).toList();
    final archived = state.timetables.where((t) => t.archived).toList();
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AlertDialog(
      title: const Text('管理课表'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: compact ? double.maxFinite : 520,
        height: compact ? 500 : 440,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('timetable-create'),
                      onPressed: () => _createTimetable(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建空课表'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('timetable-duplicate'),
                      onPressed: state.activeTimetable == null
                          ? null
                          : () => _duplicateTimetable(
                              context,
                              state.activeTimetable!,
                            ),
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                      label: const Text('复制当前课表'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const _GroupLabel(label: '正在使用'),
                  for (final timetable in current)
                    _TimetableTile(
                      timetable: timetable,
                      active: timetable.id == activeId,
                    ),
                  if (archived.isNotEmpty) ...[
                    const _GroupLabel(label: '已归档'),
                    for (final timetable in archived)
                      _TimetableTile(
                        timetable: timetable,
                        active: timetable.id == activeId,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

enum _TimetableAction { rename, archive, restore, delete }

class _TimetableTile extends StatelessWidget {
  const _TimetableTile({required this.timetable, required this.active});

  final Timetable timetable;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final end = timetable.termStart.add(
      Duration(days: timetable.totalWeeks * 7 - 1),
    );
    return ListTile(
      key: ValueKey('timetable-row-${timetable.id}'),
      leading: Icon(
        active ? Icons.check_circle : Icons.calendar_view_week_outlined,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(timetable.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${monthDayText(timetable.termStart)} - ${monthDayText(end)}'
        ' · ${timetable.courses.length} 门课',
      ),
      onTap: timetable.archived
          ? null
          : () async {
              await AppScope.read(context).setActiveTimetableId(timetable.id);
              if (context.mounted) Navigator.of(context).pop();
            },
      trailing: PopupMenuButton<_TimetableAction>(
        tooltip: '课表操作',
        onSelected: (action) async {
          switch (action) {
            case _TimetableAction.rename:
              await _renameTimetable(context, timetable);
            case _TimetableAction.archive:
              await state.setTimetableArchived(timetable.id, true);
            case _TimetableAction.restore:
              await state.setTimetableArchived(timetable.id, false);
            case _TimetableAction.delete:
              await _deleteTimetable(context, timetable);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _TimetableAction.rename,
            child: _MenuLabel(icon: Icons.edit_outlined, label: '重命名'),
          ),
          if (timetable.archived)
            const PopupMenuItem(
              value: _TimetableAction.restore,
              child: _MenuLabel(icon: Icons.unarchive_outlined, label: '恢复'),
            )
          else
            const PopupMenuItem(
              value: _TimetableAction.archive,
              child: _MenuLabel(icon: Icons.archive_outlined, label: '归档'),
            ),
          const PopupMenuItem(
            value: _TimetableAction.delete,
            child: _MenuLabel(icon: Icons.delete_outline, label: '删除'),
          ),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('timetable-name'),
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: '课表名称'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.trim();
}

Future<void> _createTimetable(BuildContext context) async {
  final state = AppScope.read(context);
  final base = state.activeTimetable;
  final name = await _askName(context, title: '新建空课表', initialValue: '新课表');
  if (name == null || name.isEmpty) return;
  final timetable = Timetable(
    id: newId('timetable'),
    name: name,
    termStart: base?.termStart ?? DateTime.now(),
    totalWeeks: base?.totalWeeks ?? 20,
    timeSlots: base?.timeSlots ?? kDefaultTimeSlots,
    showWeekend: base?.showWeekend ?? true,
  );
  await state.putTimetable(timetable);
  if (context.mounted) Navigator.of(context).pop();
}

Future<void> _duplicateTimetable(BuildContext context, Timetable source) async {
  final name = await _askName(
    context,
    title: '复制课表',
    initialValue: '${source.name} 副本',
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  await AppScope.read(context).putTimetable(
    Timetable(
      id: newId('timetable'),
      name: name,
      termStart: source.termStart,
      totalWeeks: source.totalWeeks,
      timeSlots: source.timeSlots,
      showWeekend: source.showWeekend,
      courses: source.courses,
      sessions: source.sessions,
      scheduleChanges: source.scheduleChanges,
    ),
  );
  if (context.mounted) Navigator.of(context).pop();
}

Future<void> _renameTimetable(BuildContext context, Timetable timetable) async {
  final name = await _askName(
    context,
    title: '重命名课表',
    initialValue: timetable.name,
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  await AppScope.read(context)
      .updateTimetable(timetable.id, (current) => current.copyWith(name: name));
}

Future<void> _deleteTimetable(BuildContext context, Timetable timetable) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除课表？'),
      content: Text('“${timetable.name}”及其中的课程和临时安排会被删除。关联待办会保留，但不再关联课程。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await AppScope.read(context).deleteTimetable(timetable.id);
  }
}
