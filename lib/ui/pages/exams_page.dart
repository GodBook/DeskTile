import 'package:flutter/material.dart';

import '../../core/exam_countdown.dart';
import '../../core/models/exam.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';
import '../theme.dart';

/// 考试倒计时页。
class ExamsPage extends StatelessWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = DateTime.now();
    final upcoming = upcomingExams(state.exams, now);
    final past = pastExams(state.exams, now);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Text('考试倒计时', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showExamEditor(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加考试'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.exams.isEmpty
              ? const Center(child: Text('还没有考试安排'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in upcoming) _ExamCard(countdown: c),
                    if (past.isNotEmpty)
                      ExpansionTile(
                        title: Text('已结束（${past.length}）'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          for (final e in past)
                            ListTile(
                              dense: true,
                              title: Text(e.name),
                              subtitle: Text(
                                  '${monthDayText(e.startAt)} ${hhmm(e.startAt)}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    AppScope.read(context).deleteExam(e.id),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.countdown});

  final ExamCountdown countdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = countdown.exam;
    final urgent = !countdown.started && countdown.remaining.inDays < 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showExamEditor(context, exam: e),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${monthDayText(e.startAt)} ${hhmm(e.startAt)}'
                            '${e.endAt == null ? '' : '-${hhmm(e.endAt!)}'}',
                        if (e.room != null) e.room!,
                        if (e.seat != null) '座位 ${e.seat}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (e.note != null && e.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(e.note!, style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    countdown.remainingText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: urgent
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!countdown.started)
                    Text('后开考',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showExamEditor(BuildContext context, {Exam? exam}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _ExamEditorDialog(exam: exam),
    );

class _ExamEditorDialog extends StatefulWidget {
  const _ExamEditorDialog({this.exam});

  final Exam? exam;

  @override
  State<_ExamEditorDialog> createState() => _ExamEditorDialogState();
}

class _ExamEditorDialogState extends State<_ExamEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _room;
  late final TextEditingController _seat;
  late final TextEditingController _note;
  late DateTime _date;
  late TimeOfDay _start;
  TimeOfDay? _end;

  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    _name = TextEditingController(text: e?.name ?? '');
    _room = TextEditingController(text: e?.room ?? '');
    _seat = TextEditingController(text: e?.seat ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    final start = e?.startAt ?? DateTime.now().add(const Duration(days: 7));
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = e?.endAt == null
        ? null
        : TimeOfDay(hour: e!.endAt!.hour, minute: e.endAt!.minute);
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _seat.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final exam = Exam(
      id: widget.exam?.id ?? newId('e'),
      name: name,
      startAt: _combine(_start),
      endAt: _end == null ? null : _combine(_end!),
      room: _room.text.trim().isEmpty ? null : _room.text.trim(),
      seat: _seat.text.trim().isEmpty ? null : _seat.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    await AppScope.read(context).putExam(exam);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.exam == null ? '添加考试' : '编辑考试'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '科目名称 *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(monthDayText(_date)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(_date.year - 2),
                          lastDate: DateTime(_date.year + 3),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('开考 ${_start.hour.toString().padLeft(2, '0')}:'
                          '${_start.minute.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: _start);
                        if (picked != null) setState(() => _start = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: Text(_end == null
                          ? '结束（可选）'
                          : '结束 ${_end!.hour.toString().padLeft(2, '0')}:'
                              '${_end!.minute.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _end ??
                              TimeOfDay(hour: _start.hour + 2, minute: _start.minute),
                        );
                        if (picked != null) setState(() => _end = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _room,
                      decoration: const InputDecoration(labelText: '考场'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _seat,
                      decoration: const InputDecoration(labelText: '座位号'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: '备注'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.exam != null)
          TextButton(
            onPressed: () async {
              await AppScope.read(context).deleteExam(widget.exam!.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

