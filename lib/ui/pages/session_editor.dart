import 'package:flutter/material.dart';

import '../../core/models/course.dart';
import '../../core/models/timetable.dart';
import '../../core/week_math.dart';
import '../../core/weeks_parser.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';

/// 打开课程时段编辑框。[session] 为空表示新增。
Future<void> showSessionEditor(
  BuildContext context, {
  required int week,
  CourseSession? session,
  int? day,
  int? startSection,
}) async {
  final state = AppScope.read(context);
  final timetable = state.activeTimetable;
  if (timetable == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _SessionEditorDialog(
      timetable: timetable,
      session: session,
      initialDay: day ?? session?.day ?? 1,
      initialStart: startSection ?? session?.startSection ?? 1,
      currentWeek: week,
    ),
  );
}

class _SessionEditorDialog extends StatefulWidget {
  const _SessionEditorDialog({
    required this.timetable,
    required this.session,
    required this.initialDay,
    required this.initialStart,
    required this.currentWeek,
  });

  final Timetable timetable;
  final CourseSession? session;
  final int initialDay;
  final int initialStart;
  final int currentWeek;

  @override
  State<_SessionEditorDialog> createState() => _SessionEditorDialogState();
}

class _SessionEditorDialogState extends State<_SessionEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _room;
  late final TextEditingController _weeksText;

  late int _day;
  late int _start;
  late int _end;
  late Set<int> _weeks;
  String? _weeksError;

  Timetable get t => widget.timetable;
  bool get isEditing => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    final course = s == null ? null : t.courseById(s.courseId);
    _name = TextEditingController(text: course?.name ?? '');
    _teacher = TextEditingController(text: course?.teacher ?? '');
    _room = TextEditingController(text: s?.room ?? '');
    _day = widget.initialDay;
    _start = widget.initialStart;
    _end = s?.endSection ?? widget.initialStart;
    _weeks = s?.weeks ?? allWeeks(t.totalWeeks);
    _weeksText = TextEditingController(
      text: compressRanges(_weeks)
          .map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}')
          .join(','),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _weeksText.dispose();
    super.dispose();
  }

  void _applyPreset(Set<int> weeks) {
    setState(() {
      _weeks = weeks;
      _weeksError = null;
      _weeksText.text = compressRanges(weeks)
          .map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}')
          .join(',');
    });
  }

  void _onWeeksTextChanged(String value) {
    final parsed = tryParseWeeks(value, totalWeeks: t.totalWeeks);
    setState(() {
      if (parsed == null) {
        _weeksError = '看不懂，试试 1-16 / 1-16单 / 1-8,10,12-16';
      } else {
        _weeksError = null;
        _weeks = parsed;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {});
      return;
    }
    if (_weeks.isEmpty) {
      setState(() => _weeksError = '至少选一周');
      return;
    }
    final teacher = _teacher.text.trim().isEmpty ? null : _teacher.text.trim();
    final room = _room.text.trim().isEmpty ? null : _room.text.trim();
    final start = _start;
    final end = _end < _start ? _start : _end;

    final state = AppScope.read(context);
    await state.updateActiveTimetable((current) {
      // 同名同教师的课复用同一个 Course，改名时会自动落到新的（或已有的）课上。
      var courses = [...current.courses];
      var course = courses.firstWhere(
        (c) => c.name == name && c.teacher == teacher,
        orElse: () => Course(id: '', name: ''),
      );
      if (course.id.isEmpty) {
        course = Course(
          id: newId('c'),
          name: name,
          teacher: teacher,
          colorSeed: name.hashCode,
        );
        courses.add(course);
      }

      final session = CourseSession(
        id: widget.session?.id ?? newId('s'),
        courseId: course.id,
        day: _day,
        startSection: start,
        endSection: end,
        weeks: _weeks,
        room: room,
      );

      final sessions = [
        for (final s in current.sessions)
          if (s.id == session.id) session else s,
      ];
      if (!sessions.any((s) => s.id == session.id)) sessions.add(session);

      // 清掉没有任何时段的课程，避免编辑改名后留下孤儿。
      final used = sessions.map((s) => s.courseId).toSet();
      courses = courses.where((c) => used.contains(c.id)).toList();

      return current.copyWith(courses: courses, sessions: sessions);
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final id = widget.session!.id;
    await state.updateActiveTimetable((current) {
      final sessions = current.sessions.where((s) => s.id != id).toList();
      final used = sessions.map((s) => s.courseId).toSet();
      return current.copyWith(
        sessions: sessions,
        courses: current.courses.where((c) => used.contains(c.id)).toList(),
      );
    });
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxSection = t.maxSection;
    final all = allWeeks(t.totalWeeks);
    final odd = oddWeeks(t.totalWeeks);
    final even = evenWeeks(t.totalWeeks);

    return AlertDialog(
      title: Text(isEditing ? '编辑课程' : '添加课程'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.maxFinite : 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '课程名称 *'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final teacher = TextField(
                    controller: _teacher,
                    decoration: const InputDecoration(labelText: '教师'),
                  );
                  final room = TextField(
                    controller: _room,
                    decoration: const InputDecoration(labelText: '教室'),
                  );
                  if (constraints.maxWidth < 380) {
                    return Column(
                      children: [teacher, const SizedBox(height: 12), room],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: teacher),
                      const SizedBox(width: 12),
                      Expanded(child: room),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final dayField = DropdownButtonFormField<int>(
                    initialValue: _day,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '星期'),
                    items: [
                      for (var d = 1; d <= 7; d++)
                        DropdownMenuItem(value: d, child: Text(weekDayName(d))),
                    ],
                    onChanged: (v) => setState(() => _day = v ?? _day),
                  );
                  final startField = DropdownButtonFormField<int>(
                    initialValue: _start.clamp(1, maxSection),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '开始节次'),
                    items: [
                      for (var s = 1; s <= maxSection; s++)
                        DropdownMenuItem(value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() {
                      _start = v ?? _start;
                      if (_end < _start) _end = _start;
                    }),
                  );
                  final endField = DropdownButtonFormField<int>(
                    initialValue: _end.clamp(_start, maxSection),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '结束节次'),
                    items: [
                      for (var s = _start; s <= maxSection; s++)
                        DropdownMenuItem(value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() => _end = v ?? _end),
                  );

                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        dayField,
                        const SizedBox(height: 12),
                        startField,
                        const SizedBox(height: 12),
                        endField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: dayField),
                      const SizedBox(width: 12),
                      Expanded(child: startField),
                      const SizedBox(width: 12),
                      Expanded(child: endField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '上课周次',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('每周'),
                    selected: setEquals(_weeks, all),
                    onSelected: (_) => _applyPreset(all),
                  ),
                  ChoiceChip(
                    label: const Text('单周'),
                    selected: setEquals(_weeks, odd),
                    onSelected: (_) => _applyPreset(odd),
                  ),
                  ChoiceChip(
                    label: const Text('双周'),
                    selected: setEquals(_weeks, even),
                    onSelected: (_) => _applyPreset(even),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weeksText,
                decoration: InputDecoration(
                  labelText: '自定义周次（共 ${t.totalWeeks} 周）',
                  helperText: '支持 1-16 / 1-16单 / 双 / 1-8,10,12-16',
                  errorText: _weeksError,
                ),
                onChanged: _onWeeksTextChanged,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前选中：${formatWeeks(_weeks, totalWeeks: t.totalWeeks)}'
                  '（共 ${_weeks.length} 周）'
                  '${_weeks.contains(widget.currentWeek) ? '' : ' · 本周不上'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: _delete,
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
