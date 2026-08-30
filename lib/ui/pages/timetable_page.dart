import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/agenda.dart';
import '../../core/models/timetable.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../theme.dart';
import 'schedule_change_editor.dart';
import 'session_editor.dart';
import 'timetable_manager.dart';

const _rowHeight = 58.0;
const _timeColumnWidth = 52.0;
const _headerHeight = 44.0;
const _minGridScale = 0.65;
const _maxGridScale = 2.5;
const _gridScaleStep = 0.1;

/// 周视图：左侧节次时间轴，上方周一~周日，中间是课程块。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  int? _week;
  String? _timetableId;

  int weekOf(Timetable t) =>
      _week ?? clampedWeek(t.termStart, DateTime.now(), t.totalWeeks);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.activeTimetable;
    if (t == null) {
      return const Center(child: Text('还没有课表'));
    }
    if (_timetableId != t.id) {
      _timetableId = t.id;
      _week = null;
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
                      child: Tooltip(
                        message: '管理课表',
                        child: InkWell(
                          key: const ValueKey('timetable-manager'),
                          onTap: () => showTimetableManager(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    timetable.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: timetable.courses.isEmpty ? '先添加常规课程' : '添加补课',
                      onPressed: timetable.courses.isEmpty
                          ? null
                          : () => showScheduleChangeEditor(
                              context,
                              week: week,
                              initialDate: _initialChangeDate(timetable, week),
                            ),
                      icon: const Icon(Icons.event_available, size: 20),
                    ),
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
              TextButton.icon(
                key: const ValueKey('timetable-manager'),
                onPressed: () => showTimetableManager(context),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                  timetable.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
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
              IconButton(
                tooltip: timetable.courses.isEmpty ? '先添加常规课程' : '添加补课',
                onPressed: timetable.courses.isEmpty
                    ? null
                    : () => showScheduleChangeEditor(
                        context,
                        week: week,
                        initialDate: _initialChangeDate(timetable, week),
                      ),
                icon: const Icon(Icons.event_available, size: 20),
              ),
              const SizedBox(width: 4),
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

DateTime _initialChangeDate(Timetable timetable, int week) {
  final today = weekDayOfDate(
    timetable.termStart,
    DateTime.now(),
    timetable.totalWeeks,
  );
  final day = today?.week == week ? today!.day : 1;
  return dateOfWeekDay(timetable.termStart, week, day);
}

class _Grid extends StatefulWidget {
  const _Grid({required this.timetable, required this.week});

  final Timetable timetable;
  final int week;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  double _windowsScale = 1;

  void _handleWindowsPointerSignal(PointerSignalEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows ||
        event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed ||
        event.scrollDelta.dy == 0) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (!mounted || resolvedEvent is! PointerScrollEvent) return;
      final direction = resolvedEvent.scrollDelta.dy < 0 ? 1 : -1;
      final nextScale = (_windowsScale + direction * _gridScaleStep)
          .clamp(_minGridScale, _maxGridScale)
          .toDouble();
      if (nextScale == _windowsScale) return;
      setState(() => _windowsScale = nextScale);
    });
  }

  Widget _windowsZoomRegion({required Widget child}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handleWindowsPointerSignal,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.timetable;
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

        // Android 上把完整网格交给 InteractiveViewer，双指可以缩放，单指
        // 可以平移；桌面端保留原来的横向/纵向滚动和固定表头行为。
        if (defaultTargetPlatform == TargetPlatform.android) {
          return InteractiveViewer(
            key: const ValueKey('timetable-zoom-view'),
            alignment: Alignment.topLeft,
            boundaryMargin: const EdgeInsets.all(24),
            constrained: false,
            minScale: _minGridScale,
            maxScale: _maxGridScale,
            child: SizedBox(
              width: gridWidth,
              height: _headerHeight + _rowHeight * maxSection,
              child: Column(
                children: [
                  _HeaderRow(
                    timetable: t,
                    week: widget.week,
                    dayCount: dayCount,
                    colWidth: colWidth,
                    todayDay: today?.week == widget.week ? today?.day : null,
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimeColumn(timetable: t, maxSection: maxSection),
                        for (var day = 1; day <= dayCount; day++)
                          _DayColumn(
                            timetable: t,
                            week: widget.week,
                            day: day,
                            width: colWidth,
                            maxSection: maxSection,
                            isToday:
                                today?.week == widget.week && today?.day == day,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final scale = defaultTargetPlatform == TargetPlatform.windows
            ? _windowsScale
            : 1.0;
        final scaledGridWidth = gridWidth * scale;
        final bodyHeight = _rowHeight * maxSection;

        // 表头和内容放在同一个水平视口中，两者始终使用同一滚动偏移。
        return SingleChildScrollView(
          key: const ValueKey('timetable-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: scaledGridWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                // 星期表头固定在上面，纵向滚动时不会跟着滚掉。
                _windowsZoomRegion(
                  child: SizedBox(
                    width: scaledGridWidth,
                    height: _headerHeight * scale,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: gridWidth,
                      maxWidth: gridWidth,
                      minHeight: _headerHeight,
                      maxHeight: _headerHeight,
                      child: Transform.scale(
                        key: const ValueKey('timetable-windows-header-zoom'),
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: gridWidth,
                          height: _headerHeight,
                          child: _HeaderRow(
                            timetable: t,
                            week: widget.week,
                            dayCount: dayCount,
                            colWidth: colWidth,
                            todayDay: today?.week == widget.week
                                ? today?.day
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('timetable-vertical-scroll'),
                    child: _windowsZoomRegion(
                      child: SizedBox(
                        width: scaledGridWidth,
                        height: bodyHeight * scale,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: gridWidth,
                          maxWidth: gridWidth,
                          minHeight: bodyHeight,
                          maxHeight: bodyHeight,
                          child: Transform.scale(
                            key: const ValueKey('timetable-windows-body-zoom'),
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: gridWidth,
                              height: bodyHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TimeColumn(
                                    timetable: t,
                                    maxSection: maxSection,
                                  ),
                                  for (var day = 1; day <= dayCount; day++)
                                    _DayColumn(
                                      timetable: t,
                                      week: widget.week,
                                      day: day,
                                      width: colWidth,
                                      maxSection: maxSection,
                                      isToday:
                                          today?.week == widget.week &&
                                          today?.day == day,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
    final sessions = sessionsOnWeekDay(
      timetable,
      week,
      day,
      includeChangedSources: true,
    );
    final date = dateOfWeekDay(timetable.termStart, week, day);

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
                    onLongPress: () => showScheduleChangeEditor(
                      context,
                      week: week,
                      initialDate: date,
                      initialStartSection: s,
                    ),
                    onSecondaryTap: () => showScheduleChangeEditor(
                      context,
                      week: week,
                      initialDate: date,
                      initialStartSection: s,
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
    final courseBaseColor = courseColor(
      session.course.colorSeed,
      theme.brightness,
    );
    final inactive = session.isInactive;
    final color = inactive ? theme.colorScheme.outline : courseBaseColor;
    final status = switch (session.occurrence) {
      SessionOccurrenceKind.regular => null,
      SessionOccurrenceKind.cancelled => '停课',
      SessionOccurrenceKind.rescheduledSource => '调出',
      SessionOccurrenceKind.rescheduledTarget => '调课',
      SessionOccurrenceKind.extraClass => '补课',
    };
    final change = session.change;
    final detail =
        session.occurrence == SessionOccurrenceKind.rescheduledSource &&
            change?.targetDate != null
        ? '调至 ${change!.targetDate!.month}/${change.targetDate!.day} '
              '第${change.startSection}-${change.endSection}节'
        : session.session.room;

    return Material(
      color: color.withValues(
        alpha: inactive
            ? theme.brightness == Brightness.dark
                  ? 0.2
                  : 0.1
            : theme.brightness == Brightness.dark
            ? 0.34
            : 0.16,
      ),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => session.change == null
            ? showSessionEditor(context, week: week, session: session.session)
            : showScheduleChangeEditor(
                context,
                week: week,
                change: session.change,
              ),
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
              final showDetail =
                  box.maxHeight >= 46 && detail != null && detail.isNotEmpty;
              final showTeacher =
                  box.maxHeight >= 86 &&
                  (session.course.teacher?.isNotEmpty ?? false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          session.course.name,
                          maxLines: box.maxHeight >= 86 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            decoration: inactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: inactive ? theme.colorScheme.outline : color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (showDetail)
                    Text(
                      detail,
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
