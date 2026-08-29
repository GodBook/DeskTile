import 'package:flutter/material.dart';

import '../../core/agenda.dart';
import '../../core/models/course.dart';
import '../../core/models/schedule_change.dart';
import '../../core/models/timetable.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';

Future<void> showScheduleChangeEditor(
  BuildContext context, {
  required int week,
  CourseSession? sourceSession,
  ScheduleChange? change,
  DateTime? initialDate,
  int? initialStartSection,
}) async {
  final state = AppScope.read(context);
  final timetable = state.activeTimetable;
  if (timetable == null || timetable.courses.isEmpty) return;

  final source =
      sourceSession ??
      (change?.originalSessionId == null
          ? null
          : timetable.sessionById(change!.originalSessionId!));
  final sourceDate =
      change?.originalDate ??
      (source == null
          ? null
          : dateOfWeekDay(timetable.termStart, week, source.day));
  final fallbackDate =
      initialDate ??
      sourceDate ??
      dateOfWeekDay(timetable.termStart, week, DateTime.now().weekday);

  await showDialog<void>(
    context: context,
    builder: (context) => _ScheduleChangeDialog(
      timetable: timetable,
      sourceSession: source,
      sourceDate: sourceDate,
      change: change,
      initialDate: fallbackDate,
      initialStartSection: initialStartSection,
    ),
  );
}

class _ScheduleChangeDialog extends StatefulWidget {
  const _ScheduleChangeDialog({
    required this.timetable,
    required this.sourceSession,
    required this.sourceDate,
    required this.change,
    required this.initialDate,
    required this.initialStartSection,
  });

  final Timetable timetable;
  final CourseSession? sourceSession;
  final DateTime? sourceDate;
  final ScheduleChange? change;
  final DateTime initialDate;
  final int? initialStartSection;

  @override
  State<_ScheduleChangeDialog> createState() => _ScheduleChangeDialogState();
}

class _ScheduleChangeDialogState extends State<_ScheduleChangeDialog> {
  late ScheduleChangeType _type;
  late String _courseId;
  late DateTime _targetDate;
  late int _start;
  late int _end;
  late final TextEditingController _room;

  Timetable get timetable => widget.timetable;
  bool get hasSource => widget.sourceSession != null;
  bool get isEditing => widget.change != null;

  @override
  void initState() {
    super.initState();
    final change = widget.change;
    final source = widget.sourceSession;
    _type =
        change?.type ??
        (source == null
            ? ScheduleChangeType.extraClass
            : ScheduleChangeType.reschedule);
    _courseId =
        change?.courseId ?? source?.courseId ?? timetable.courses.first.id;
    _targetDate = change?.targetDate ?? widget.initialDate;
    _start =
        change?.startSection ??
        widget.initialStartSection ??
        source?.startSection ??
        1;
    _end = change?.endSection ?? source?.endSection ?? _start;
    _room = TextEditingController(text: change?.room ?? source?.room ?? '');
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final first = timetable.termStart;
    final last = first.add(Duration(days: timetable.totalWeeks * 7 - 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate.isBefore(first) || _targetDate.isAfter(last)
          ? first
          : _targetDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _targetDate = dateOnly(picked));
  }

  List<ResolvedSession> get _conflicts {
    if (_type == ScheduleChangeType.cancellation) return const [];
    final source = widget.sourceSession;
    final sourceDate = widget.sourceDate;
    return sessionsOnDate(timetable, _targetDate).where((item) {
      if (item.change?.id == widget.change?.id) return false;
      if (source != null &&
          item.session.id == source.id &&
          sourceDate != null &&
          _sameDate(sourceDate, _targetDate)) {
        return false;
      }
      return item.session.startSection <= _end &&
          item.session.endSection >= _start;
    }).toList();
  }

  Future<void> _save() async {
    final source = widget.sourceSession;
    final sourceDate = widget.sourceDate;
    final id = widget.change?.id ?? newId('change');
    final room = _room.text.trim().isEmpty ? null : _room.text.trim();
    final ScheduleChange next;

    switch (_type) {
      case ScheduleChangeType.cancellation:
        if (source == null || sourceDate == null) return;
        next = ScheduleChange.cancellation(
          id: id,
          originalSessionId: source.id,
          originalDate: sourceDate,
        );
      case ScheduleChangeType.reschedule:
        if (source == null || sourceDate == null) return;
        next = ScheduleChange.reschedule(
          id: id,
          originalSessionId: source.id,
          originalDate: sourceDate,
          targetDate: _targetDate,
          startSection: _start,
          endSection: _end < _start ? _start : _end,
          room: room,
        );
      case ScheduleChangeType.extraClass:
        next = ScheduleChange.extraClass(
          id: id,
          courseId: _courseId,
          targetDate: _targetDate,
          startSection: _start,
          endSection: _end < _start ? _start : _end,
          room: room,
        );
    }

    final state = AppScope.read(context);
    await state.updateActiveTimetable((current) {
      final changes = <ScheduleChange>[
        for (final existing in current.scheduleChanges)
          if (existing.id != next.id && !_sameSourceOccurrence(existing, next))
            existing,
        next,
      ];
      return current.copyWith(scheduleChanges: changes);
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.change!.id;
    final state = AppScope.read(context);
    await state.updateActiveTimetable((current) {
      final scheduleChanges = current.scheduleChanges
          .where((change) => change.id != id)
          .toList();
      final usedCourseIds =
          current.sessions.map((session) => session.courseId).toSet()..addAll(
            scheduleChanges
                .where((change) => change.courseId != null)
                .map((change) => change.courseId!),
          );
      return current.copyWith(
        scheduleChanges: scheduleChanges,
        courses: current.courses
            .where((course) => usedCourseIds.contains(course.id))
            .toList(),
      );
    });
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.sourceSession;
    final sourceCourse = source == null
        ? null
        : timetable.courseById(source.courseId);
    final maxSection = timetable.maxSection;
    final conflicts = _conflicts;

    return AlertDialog(
      title: Text(
        isEditing
            ? '编辑临时安排'
            : hasSource
            ? '调整本次课程'
            : '添加补课',
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.maxFinite : 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (source != null && widget.sourceDate != null) ...[
                Text(
                  sourceCourse?.name ?? '未知课程',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '原安排：${_dateText(widget.sourceDate!)} · '
                  '第${source.startSection}-${source.endSection}节'
                  '${source.room == null ? '' : ' · ${source.room}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<ScheduleChangeType>(
                  segments: const [
                    ButtonSegment(
                      value: ScheduleChangeType.cancellation,
                      icon: Icon(Icons.event_busy, size: 18),
                      label: Text('停课'),
                    ),
                    ButtonSegment(
                      value: ScheduleChangeType.reschedule,
                      icon: Icon(Icons.event_repeat, size: 18),
                      label: Text('调课'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selected) =>
                      setState(() => _type = selected.single),
                ),
              ],
              if (_type != ScheduleChangeType.cancellation) ...[
                if (!hasSource) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('extra-class-course'),
                    initialValue: _courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '课程'),
                    items: [
                      for (final course in timetable.courses)
                        DropdownMenuItem(
                          value: course.id,
                          child: Text(
                            course.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _courseId = value ?? _courseId),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  key: const ValueKey('schedule-change-date'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(_dateText(_targetDate)),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final start = DropdownButtonFormField<int>(
                      key: const ValueKey('schedule-change-start'),
                      initialValue: _start.clamp(1, maxSection),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '开始节次'),
                      items: [
                        for (var section = 1; section <= maxSection; section++)
                          DropdownMenuItem(
                            value: section,
                            child: Text('第 $section 节'),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _start = value ?? _start;
                        if (_end < _start) _end = _start;
                      }),
                    );
                    final end = DropdownButtonFormField<int>(
                      key: ValueKey('schedule-change-end-$_start'),
                      initialValue: _end.clamp(_start, maxSection),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '结束节次'),
                      items: [
                        for (
                          var section = _start;
                          section <= maxSection;
                          section++
                        )
                          DropdownMenuItem(
                            value: section,
                            child: Text('第 $section 节'),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _end = value ?? _end),
                    );
                    if (constraints.maxWidth < 340) {
                      return Column(
                        children: [start, const SizedBox(height: 12), end],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: start),
                        const SizedBox(width: 12),
                        Expanded(child: end),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: '教室'),
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '与 ${conflicts.map((item) => item.course.name).toSet().join('、')} 冲突',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(hasSource ? Icons.undo : Icons.delete_outline, size: 18),
            label: Text(hasSource ? '恢复原安排' : '删除补课'),
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

bool _sameSourceOccurrence(ScheduleChange left, ScheduleChange right) {
  if (left.type == ScheduleChangeType.extraClass ||
      right.type == ScheduleChangeType.extraClass) {
    return false;
  }
  return left.originalSessionId == right.originalSessionId &&
      left.originalDate != null &&
      right.originalDate != null &&
      _sameDate(left.originalDate!, right.originalDate!);
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dateText(DateTime date) =>
    '${date.month}月${date.day}日 ${weekDayName(date.weekday)}';
