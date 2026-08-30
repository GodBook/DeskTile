import 'package:flutter/material.dart';

import '../../core/academic_calendar.dart';
import '../../core/models/academic_calendar_event.dart';
import '../../core/models/timetable.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';
import '../theme.dart';

Future<void> openAcademicCalendarPage(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('学期校历')),
          body: const SafeArea(child: AcademicCalendarPage()),
        ),
      ),
    );

class AcademicCalendarPage extends StatelessWidget {
  const AcademicCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final timetable = AppScope.of(context).activeTimetable;
    if (timetable == null) return const Center(child: Text('还没有课表'));

    final events = [...timetable.academicCalendarEvents]
      ..sort((left, right) {
        final date = left.startDate.compareTo(right.startDate);
        return date != 0 ? date : left.endDate.compareTo(right.endDate);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _CalendarSummary(timetable: timetable),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '校历安排',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('academic-calendar-add'),
              onPressed: () => showAcademicCalendarEventEditor(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加安排'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          _EmptyCalendar(onAdd: () => showAcademicCalendarEventEditor(context))
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < events.length; index++) ...[
                  _CalendarEventTile(
                    timetable: timetable,
                    event: events[index],
                  ),
                  if (index != events.length - 1)
                    const Divider(height: 1, indent: 56),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarSummary extends StatelessWidget {
  const _CalendarSummary({required this.timetable});

  final Timetable timetable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = timetableEndDate(timetable);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.date_range_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    timetable.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${monthDayText(timetable.termStart)} - ${monthDayText(end)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SummaryMetric(
                  value: '${timetable.academicCalendarEvents.length}',
                  label: '校历项',
                ),
                _SummaryMetric(
                  value: '${suspendedCalendarDayCount(timetable)}',
                  label: '停课天',
                ),
                _SummaryMetric(
                  value: '${suspendedRegularSessionCount(timetable)}',
                  label: '课程次',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _EmptyCalendar extends StatelessWidget {
  const _EmptyCalendar({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 54),
    child: Column(
      children: [
        Icon(
          Icons.event_available_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text('还没有校历安排', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          '添加假期、考试周或批量停课',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加第一项'),
        ),
      ],
    ),
  );
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({required this.timetable, required this.event});

  final Timetable timetable;
  final AcademicCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final affected = affectedRegularSessionCount(timetable, event);
    return ListTile(
      key: ValueKey('academic-calendar-event-${event.id}'),
      leading: Icon(
        _eventIcon(event.type),
        color: event.suspendsClasses
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary,
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_dateRangeText(event.startDate, event.endDate)} · '
        '${_eventTypeLabel(event.type)} · '
        '${event.suspendsClasses ? '停课 $affected 次' : '仅标记'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => showAcademicCalendarEventEditor(context, event: event),
      trailing: PopupMenuButton<_CalendarEventAction>(
        tooltip: '校历操作',
        onSelected: (action) {
          switch (action) {
            case _CalendarEventAction.edit:
              showAcademicCalendarEventEditor(context, event: event);
            case _CalendarEventAction.delete:
              _confirmDeleteCalendarEvent(context, event);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _CalendarEventAction.edit,
            child: _MenuLabel(icon: Icons.edit_outlined, label: '编辑'),
          ),
          PopupMenuItem(
            value: _CalendarEventAction.delete,
            child: _MenuLabel(icon: Icons.delete_outline, label: '删除'),
          ),
        ],
      ),
    );
  }
}

enum _CalendarEventAction { edit, delete }

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

Future<void> showAcademicCalendarEventEditor(
  BuildContext context, {
  AcademicCalendarEvent? event,
}) async {
  final timetable = AppScope.read(context).activeTimetable;
  if (timetable == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _AcademicCalendarEventEditor(timetable: timetable, event: event),
  );
}

class _AcademicCalendarEventEditor extends StatefulWidget {
  const _AcademicCalendarEventEditor({required this.timetable, this.event});

  final Timetable timetable;
  final AcademicCalendarEvent? event;

  @override
  State<_AcademicCalendarEventEditor> createState() =>
      _AcademicCalendarEventEditorState();
}

class _AcademicCalendarEventEditorState
    extends State<_AcademicCalendarEventEditor> {
  late final TextEditingController _titleController;
  late AcademicCalendarEventType _type;
  late DateTimeRange _range;
  late bool _suspendsClasses;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final first = widget.timetable.termStart;
    final last = timetableEndDate(widget.timetable);
    final today = dateOnly(DateTime.now());
    final initial = today.isBefore(first)
        ? first
        : today.isAfter(last)
        ? last
        : today;
    _titleController = TextEditingController(text: event?.title ?? '');
    _type = event?.type ?? AcademicCalendarEventType.holiday;
    _range = DateTimeRange(
      start: event?.startDate ?? initial,
      end: event?.endDate ?? initial,
    );
    _suspendsClasses = event?.suspendsClasses ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  AcademicCalendarEvent get _draft => AcademicCalendarEvent(
    id: widget.event?.id ?? 'preview',
    title: _titleController.text.trim(),
    type: _type,
    startDate: _range.start,
    endDate: _range.end,
    suspendsClasses: _suspendsClasses,
  );

  Future<void> _pickRange() async {
    final first = widget.timetable.termStart;
    final last = timetableEndDate(widget.timetable);
    final initialStart = _range.start.isBefore(first)
        ? first
        : _range.start.isAfter(last)
        ? last
        : _range.start;
    final initialEnd = _range.end.isBefore(initialStart)
        ? initialStart
        : _range.end.isAfter(last)
        ? last
        : _range.end;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: '选择校历日期范围',
      saveText: '确定',
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请输入安排名称');
      return;
    }
    final event = AcademicCalendarEvent(
      id: widget.event?.id ?? newId('calendar'),
      title: title,
      type: _type,
      startDate: _range.start,
      endDate: _range.end,
      suspendsClasses: _suspendsClasses,
    );
    await AppScope.read(context).updateActiveTimetable((timetable) {
      final exists = timetable.academicCalendarEvents.any(
        (item) => item.id == event.id,
      );
      final events = exists
          ? [
              for (final item in timetable.academicCalendarEvents)
                if (item.id == event.id) event else item,
            ]
          : [...timetable.academicCalendarEvents, event];
      events.sort((left, right) => left.startDate.compareTo(right.startDate));
      return timetable.copyWith(academicCalendarEvents: events);
    });
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final affected = affectedRegularSessionCount(widget.timetable, _draft);
    return AlertDialog(
      title: Text(widget.event == null ? '添加校历安排' : '编辑校历安排'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AcademicCalendarEventType>(
                key: const ValueKey('academic-calendar-type'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: '类型'),
                items: [
                  for (final value in AcademicCalendarEventType.values)
                    DropdownMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(_eventIcon(value), size: 18),
                          const SizedBox(width: 8),
                          Text(_eventTypeLabel(value)),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('academic-calendar-title'),
                controller: _titleController,
                autofocus: widget.event == null,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: '安排名称',
                  hintText: '如：国庆假期',
                  errorText: _titleError,
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 4),
              InkWell(
                key: const ValueKey('academic-calendar-date-range'),
                borderRadius: BorderRadius.circular(8),
                onTap: _pickRange,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '日期范围',
                    prefixIcon: Icon(Icons.date_range_outlined),
                    suffixIcon: Icon(Icons.edit_calendar_outlined),
                  ),
                  child: Text(_dateRangeText(_range.start, _range.end)),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('暂停常规课程'),
                subtitle: const Text('补课和调入课程不受影响'),
                value: _suspendsClasses,
                onChanged: (value) => setState(() => _suspendsClasses = value),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _suspendsClasses ? '将暂停 $affected 次常规课程' : '仅在校历中标记，不改变课程安排',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('academic-calendar-save'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteCalendarEvent(
  BuildContext context,
  AcademicCalendarEvent event,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除校历安排？'),
      content: Text('“${event.title}”造成的批量停课会一并撤销。'),
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
  if (confirmed != true || !context.mounted) return;
  await AppScope.read(context).updateActiveTimetable(
    (timetable) => timetable.copyWith(
      academicCalendarEvents: timetable.academicCalendarEvents
          .where((item) => item.id != event.id)
          .toList(),
    ),
  );
}

String _eventTypeLabel(AcademicCalendarEventType type) => switch (type) {
  AcademicCalendarEventType.holiday => '假期',
  AcademicCalendarEventType.examWeek => '考试周',
  AcademicCalendarEventType.suspension => '停课安排',
  AcademicCalendarEventType.other => '其他',
};

IconData _eventIcon(AcademicCalendarEventType type) => switch (type) {
  AcademicCalendarEventType.holiday => Icons.beach_access_outlined,
  AcademicCalendarEventType.examWeek => Icons.fact_check_outlined,
  AcademicCalendarEventType.suspension => Icons.event_busy_outlined,
  AcademicCalendarEventType.other => Icons.event_note_outlined,
};

String _dateRangeText(DateTime start, DateTime end) {
  final first = '${start.year}年${start.month}月${start.day}日';
  if (start == end) return first;
  final last = start.year == end.year
      ? '${end.month}月${end.day}日'
      : '${end.year}年${end.month}月${end.day}日';
  return '$first - $last';
}
