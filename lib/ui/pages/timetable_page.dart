import 'package:flutter/material.dart';

import '../../core/agenda.dart';
import '../../core/models/timetable.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../theme.dart';
import 'session_editor.dart';

const _rowHeight = 58.0;
const _timeColumnWidth = 52.0;
const _headerHeight = 44.0;

/// 周视图：左侧节次时间轴，上方周一~周日，中间是课程块。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  int? _week;

  int weekOf(Timetable t) =>
      _week ?? clampedWeek(t.termStart, DateTime.now(), t.totalWeeks);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.activeTimetable;
    if (t == null) {
      return const Center(child: Text('还没有课表'));
    }
    final week = weekOf(t).clamp(1, t.totalWeeks);

    return Column(
      children: [
        _Toolbar(
          timetable: t,
          week: week,
          onWeek: (w) => setState(() => _week = w.clamp(1, t.totalWeeks)),
          onToday: () => setState(() => _week = null),
        ),
        const Divider(height: 1),
        Expanded(
          child: _Grid(timetable: t, week: week),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  static const _compactBreakpoint = 620.0;

  const _Toolbar({
    required this.timetable,
    required this.week,
    required this.onWeek,
    required this.onToday,
  });

  final Timetable timetable;
  final int week;
  final ValueChanged<int> onWeek;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final realWeek = currentWeek(
      timetable.termStart,
      DateTime.now(),
      timetable.totalWeeks,
    );
    final monday = dateOfWeekDay(timetable.termStart, week, 1);
    final sunday = dateOfWeekDay(timetable.termStart, week, 7);

    final weekLabel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '第 $week 周 · ${week.isOdd ? '单周' : '双周'}',
          style: theme.textTheme.titleSmall,
        ),
        Text(
          '${monthDayText(monday)} - ${monthDayText(sunday)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactBreakpoint) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        timetable.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => showSessionEditor(context, week: week),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加课程'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一周',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: week > 1 ? () => onWeek(week - 1) : null,
                    ),
                    Expanded(child: Center(child: weekLabel)),
                    IconButton(
                      tooltip: '下一周',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: week < timetable.totalWeeks
                          ? () => onWeek(week + 1)
                          : null,
                    ),
                    IconButton(
                      tooltip: realWeek == null ? '不在学期内' : '回到本周',
                      onPressed: onToday,
                      icon: const Icon(Icons.today, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Text(timetable.name, style: theme.textTheme.titleMedium),
              const SizedBox(width: 16),
              IconButton(
                tooltip: '上一周',
                icon: const Icon(Icons.chevron_left),
                onPressed: week > 1 ? () => onWeek(week - 1) : null,
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 96),
                alignment: Alignment.center,
                child: weekLabel,
              ),
              IconButton(
                tooltip: '下一周',
                icon: const Icon(Icons.chevron_right),
                onPressed: week < timetable.totalWeeks
                    ? () => onWeek(week + 1)
                    : null,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today, size: 18),
                label: Text(realWeek == null ? '不在学期内' : '回到本周'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => showSessionEditor(context, week: week),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加课程'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.timetable, required this.week});

  final Timetable timetable;
  final int week;

  @override
  Widget build(BuildContext context) {
    final t = timetable;
    final dayCount = t.showWeekend ? 7 : 5;
    final maxSection = t.maxSection;
    if (maxSection == 0) {
      return const Center(child: Text('作息表是空的，先到设置里添加节次时间'));
    }
    final today = weekDayOfDate(t.termStart, DateTime.now(), t.totalWeeks);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableColWidth =
            (constraints.maxWidth - _timeColumnWidth) / dayCount;
        final colWidth = availableColWidth < 96 ? 96.0 : availableColWidth;
        final gridWidth = _timeColumnWidth + colWidth * dayCount;

        // 表头和内容放在同一个水平视口中，两者始终使用同一滚动偏移。
        return SingleChildScrollView(
          key: const ValueKey('timetable-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                // 星期表头固定在上面，纵向滚动时不会跟着滚掉。
                _HeaderRow(
                  timetable: t,
                  week: week,
                  dayCount: dayCount,
                  colWidth: colWidth,
                  todayDay: today?.week == week ? today?.day : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimeColumn(timetable: t, maxSection: maxSection),
                        for (var day = 1; day <= dayCount; day++)
                          _DayColumn(
                            timetable: t,
                            week: week,
                            day: day,
                            width: colWidth,
                            maxSection: maxSection,
                            isToday: today?.week == week && today?.day == day,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.timetable,
    required this.week,
    required this.dayCount,
    required this.colWidth,
    required this.todayDay,
  });

  final Timetable timetable;
  final int week;
  final int dayCount;
  final double colWidth;
  final int? todayDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          const SizedBox(width: _timeColumnWidth),
          for (var day = 1; day <= dayCount; day++)
            SizedBox(
              width: colWidth,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: day == todayDay
                      ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        )
                      : null,
                  border: Border(
                    left: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekDayName(day),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: day == todayDay
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        monthDayText(
                          dateOfWeekDay(timetable.termStart, week, day),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.timetable, required this.maxSection});

  final Timetable timetable;
  final int maxSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _timeColumnWidth,
      child: Column(
        children: [
          for (var s = 1; s <= maxSection; s++)
            Container(
              height: _rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$s', style: theme.textTheme.labelMedium),
                    if (timetable.slotAt(s) != null) ...[
                      Text(
                        timetable.slotAt(s)!.startText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        timetable.slotAt(s)!.endText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.timetable,
    required this.week,
    required this.day,
    required this.width,
    required this.maxSection,
    required this.isToday,
  });

  final Timetable timetable;
  final int week;
  final int day;
  final double width;
  final int maxSection;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = sessionsOnWeekDay(timetable, week, day);

    return SizedBox(
      width: width,
      height: _rowHeight * maxSection,
      child: Stack(
        children: [
          // 背景：空格子，点一下就是在这个位置加课。
          Column(
            children: [
              for (var s = 1; s <= maxSection; s++)
                Container(
                  height: _rowHeight,
                  decoration: BoxDecoration(
                    color: isToday
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.14,
                          )
                        : null,
                    border: Border(
                      top: BorderSide(color: theme.dividerColor, width: 0.5),
                      left: BorderSide(color: theme.dividerColor, width: 0.5),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => showSessionEditor(
                      context,
                      week: week,
                      day: day,
                      startSection: s,
                    ),
                  ),
                ),
            ],
          ),
          for (final rs in sessions)
            Positioned(
              top: (rs.session.startSection - 1) * _rowHeight + 1,
              height: rs.session.sectionCount * _rowHeight - 3,
              left: 2,
              right: 2,
              child: _CourseBlock(session: rs, week: week),
            ),
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.session, required this.week});

  final ResolvedSession session;
  final int week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = courseColor(session.course.colorSeed, theme.brightness);
    final room = session.session.room;

    return Material(
      color: color.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.34 : 0.16,
      ),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            showSessionEditor(context, week: week, session: session.session),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          // 一节课的格子只有 58 逻辑像素高，塞不下课名+教室+教师。
          // 按可用高度决定显示到哪一层，而不是硬塞导致溢出。
          child: LayoutBuilder(
            builder: (context, box) {
              final showRoom =
                  box.maxHeight >= 46 && room != null && room.isNotEmpty;
              final showTeacher =
                  box.maxHeight >= 86 &&
                  (session.course.teacher?.isNotEmpty ?? false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      session.course.name,
                      maxLines: box.maxHeight >= 86 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (showRoom)
                    Text(
                      room,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (showTeacher)
                    Text(
                      session.course.teacher!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
