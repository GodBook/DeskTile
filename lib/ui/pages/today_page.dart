import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/agenda.dart';
import '../../core/exam_countdown.dart';
import '../../core/models/task_item.dart';
import '../../core/models/timetable.dart';
import '../../core/task_query.dart';
import '../../core/today_overview.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../../platform/notifications.dart';
import '../theme.dart';
import 'exams_page.dart';
import 'schedule_change_editor.dart';
import 'session_editor.dart';
import 'tasks_page.dart';
import 'timetable_manager.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.reminders});

  final ReminderService reminders;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final timetable = state.activeTimetable;
    final now = DateTime.now();
    final overview = buildTodayOverview(
      timetable: timetable,
      tasks: state.tasks,
      exams: state.exams,
      now: now,
    );
    final weekDay = timetable == null
        ? null
        : weekDayOfDate(timetable.termStart, now, timetable.totalWeeks);

    return Column(
      children: [
        _TodayHeader(
          now: now,
          week: weekDay?.week,
          timetableName: timetable?.name,
          onAddTask: () => showTaskEditor(context, reminders: widget.reminders),
        ),
        const Divider(height: 1),
        _NowStrip(timetable: timetable, now: now),
        Expanded(
          child: ListView(
            key: const ValueKey('today-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _SectionTitle(
                icon: Icons.school_outlined,
                label: '今天课程',
                count: overview.sessions.length,
              ),
              if (overview.sessions.isEmpty)
                const _EmptyLine(label: '今天没有课程安排')
              else
                for (final session in overview.sessions)
                  _CourseTimelineRow(
                    timetableWeek: weekDay?.week,
                    session: session,
                    now: now,
                  ),
              if (overview.dueTasks.isNotEmpty) ...[
                _SectionTitle(
                  icon: Icons.pending_actions_outlined,
                  label: '截止事项',
                  count: overview.dueTasks.length,
                ),
                for (final task in overview.dueTasks)
                  _TaskTimelineRow(
                    task: task,
                    now: now,
                    reminders: widget.reminders,
                  ),
              ],
              if (overview.upcomingExams.isNotEmpty) ...[
                _SectionTitle(
                  icon: Icons.event_note_outlined,
                  label: '近期考试',
                  count: overview.upcomingExams.length,
                ),
                for (final exam in overview.upcomingExams)
                  _ExamTimelineRow(countdown: exam),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.now,
    required this.week,
    required this.timetableName,
    required this.onAddTask,
  });

  final DateTime now;
  final int? week;
  final String? timetableName;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今天', style: theme.textTheme.titleMedium),
                  Text(
                    '${now.month}月${now.day}日 · ${weekDayName(now.weekday)}'
                    '${week == null ? '' : ' · 第 $week 周'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (timetableName != null && constraints.maxWidth >= 440)
              Flexible(
                child: TextButton.icon(
                  key: const ValueKey('today-timetable-manager'),
                  onPressed: () => showTimetableManager(context),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: Text(
                    timetableName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            else if (timetableName != null)
              IconButton(
                key: const ValueKey('today-timetable-manager'),
                tooltip: '管理课表',
                onPressed: () => showTimetableManager(context),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            IconButton(
              tooltip: '添加事项',
              onPressed: onAddTask,
              icon: const Icon(Icons.add_task_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.timetable, required this.now});

  final Timetable? timetable;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final table = timetable;
    final current = table == null ? null : currentSession(table, now);
    final next = table == null ? null : nextSession(table, now);
    final item = current ?? next;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(
            current == null
                ? Icons.schedule_outlined
                : Icons.play_circle_outline,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: item == null
                ? const Text('接下来没有课程')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${current == null ? '下一节' : '正在上'} · ${item.session.course.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          item.session.timeText,
                          if (item.session.session.room?.trim().isNotEmpty ==
                              true)
                            item.session.session.room!.trim(),
                          if (!_sameDate(item.date, now))
                            weekDayName(item.date.weekday),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 5),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          '$label  $count',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(74, 12, 0, 14),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

class _CourseTimelineRow extends StatelessWidget {
  const _CourseTimelineRow({
    required this.timetableWeek,
    required this.session,
    required this.now,
  });

  final int? timetableWeek;
  final ResolvedSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = session.isInactive
        ? theme.colorScheme.outline
        : courseColor(session.course.colorSeed, theme.brightness);
    final label = switch (session.occurrence) {
      SessionOccurrenceKind.cancelled => '已停课',
      SessionOccurrenceKind.rescheduledSource => '已调至其他时间',
      SessionOccurrenceKind.rescheduledTarget => '临时调课',
      SessionOccurrenceKind.extraClass => '临时补课',
      SessionOccurrenceKind.regular => null,
    };
    return _TimelineRow(
      time: session.startSlot.startText,
      color: color,
      onTap: timetableWeek == null
          ? null
          : () {
              final change = session.change;
              if (change != null) {
                showScheduleChangeEditor(
                  context,
                  week: timetableWeek!,
                  change: change,
                );
              } else {
                showSessionEditor(
                  context,
                  week: timetableWeek!,
                  session: session.session,
                );
              }
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.course.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: session.isInactive
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              session.timeText,
              session.sectionText,
              if (session.session.room?.trim().isNotEmpty == true)
                session.session.room!.trim(),
              ...?label == null ? null : [label],
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: session.isInactive
                  ? theme.colorScheme.outline
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTimelineRow extends StatelessWidget {
  const _TaskTimelineRow({
    required this.task,
    required this.now,
    required this.reminders,
  });

  final TaskItem task;
  final DateTime now;
  final ReminderService reminders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = taskGroupOf(task, now) == TaskGroup.overdue;
    return _TimelineRow(
      time: _timelineTime(task.dueAt!),
      color: overdue ? theme.colorScheme.error : theme.colorScheme.secondary,
      leading: Checkbox(
        key: ValueKey('today-task-checkbox-${task.id}'),
        value: false,
        onChanged: (value) =>
            AppScope.read(context).setTaskCompleted(task.id, value ?? false),
      ),
      onTap: () => showTaskEditor(context, task: task, reminders: reminders),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            overdue
                ? '已逾期 · ${_dateTimeLabel(task.dueAt!)}'
                : _dateTimeLabel(task.dueAt!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: overdue
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamTimelineRow extends StatelessWidget {
  const _ExamTimelineRow({required this.countdown});

  final ExamCountdown countdown;

  @override
  Widget build(BuildContext context) {
    final exam = countdown.exam;
    final theme = Theme.of(context);
    return _TimelineRow(
      time: '${exam.startAt.month}/${exam.startAt.day}',
      color: theme.colorScheme.tertiary,
      onTap: () => showExamEditor(context, exam: exam),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            [
              '${monthDayText(exam.startAt)} ${hhmm(exam.startAt)}',
              countdown.remainingText,
              if (exam.room?.trim().isNotEmpty == true) exam.room!.trim(),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.color,
    required this.child,
    this.leading,
    this.onTap,
  });

  final String time;
  final Color color;
  final Widget child;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 88,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 58,
              child: Padding(
                padding: const EdgeInsets.only(top: 17, right: 8),
                child: Text(
                  time,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            if (leading != null)
              Align(alignment: Alignment.center, child: leading!),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _timelineTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _dateTimeLabel(DateTime value) =>
    '${value.month}月${value.day}日 ${_timelineTime(value)}';

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
