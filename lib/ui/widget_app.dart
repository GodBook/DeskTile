import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/agenda.dart';
import '../core/exam_countdown.dart';
import '../core/models/settings.dart';
import '../core/week_math.dart';
import '../data/app_state.dart';
import '../data/widget_position.dart';
import '../platform/single_instance.dart';
import 'theme.dart';

/// 桌面挂件。整个界面就是一张圆角卡片，任意位置都能拖动。
class WidgetApp extends StatelessWidget {
  const WidgetApp({
    super.key,
    required this.state,
    required this.positionStore,
  });

  final AppState state;
  final WidgetPositionStore positionStore;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: themeModeOf(state.settings.theme),
          home: _WidgetSurface(positionStore: positionStore),
        ),
      ),
    );
  }
}

class _WidgetSurface extends StatefulWidget {
  const _WidgetSurface({required this.positionStore});

  final WidgetPositionStore positionStore;

  @override
  State<_WidgetSurface> createState() => _WidgetSurfaceState();
}

class _WidgetSurfaceState extends State<_WidgetSurface> with WindowListener {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 倒计时要走字，20 秒刷一次足够，也不费电。
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    windowManager.getPosition().then(widget.positionStore.save);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final mini = state.settings.widgetForm == WidgetForm.mini;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            child: mini ? const _MiniBody() : const _StandardBody(),
          ),
        ),
      ),
    );
  }
}

class _StandardBody extends StatelessWidget {
  const _StandardBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(),
        SizedBox(height: 6),
        _NextUp(),
        SizedBox(height: 10),
        Expanded(child: _TodayList()),
        _ExamLine(),
      ],
    );
  }
}

class _MiniBody extends StatelessWidget {
  const _MiniBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(),
        SizedBox(height: 4),
        _NextUp(compact: true),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.activeTimetable;
    final now = DateTime.now();
    final week = t == null ? null : currentWeek(t.termStart, now, t.totalWeeks);
    final parity = week == null ? '' : (week.isOdd ? ' · 单周' : ' · 双周');
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                week == null
                    ? '未在学期内'
                    : '第 $week 周 · ${weekDayName(now.weekday)}$parity',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                monthDayText(now),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '打开主窗口',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.open_in_new),
          onPressed: ModeLauncher.openMainWindow,
        ),
      ],
    );
  }
}

/// 「正在上课」或「下一节」。挂件最显眼的一块。
class _NextUp extends StatelessWidget {
  const _NextUp({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).activeTimetable;
    final theme = Theme.of(context);
    final now = DateTime.now();

    if (t == null) return const SizedBox.shrink();

    final current = currentSession(t, now);
    final next = nextSession(t, now);
    final item = current ?? next;
    if (item == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.centerLeft,
        child: Text(
          '接下来没有课了 🎉',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    final s = item.session;
    final isNow = current != null;
    final target = isNow ? s.endOn(item.date) : s.startOn(item.date);
    final delta = target.difference(now);
    final sameDay = daysBetween(now, item.date) == 0;
    final label = isNow
        ? '正在上课 · 还有 ${formatRemaining(delta)} 下课'
        : sameDay
            ? '下一节 · ${formatRemaining(delta)}后'
            : '${weekDayName(item.date.weekday)} · ${formatRemaining(delta)}后';

    final color = courseColor(s.course.colorSeed, theme.brightness);

    return Row(
      children: [
        Container(
          width: 4,
          height: compact ? 46 : 58,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color)),
              Text(
                s.course.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  if (s.session.room != null) s.session.room!,
                  s.timeText,
                  s.sectionText,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 今日剩余课程。
class _TodayList extends StatelessWidget {
  const _TodayList();

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).activeTimetable;
    final theme = Theme.of(context);
    if (t == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = agendaForDate(t, now);
    if (today.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('今天没有课',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('今日课程',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: today.length,
            itemBuilder: (context, i) {
              final item = today[i];
              final s = item.session;
              final done = s.endOn(item.date).isBefore(now);
              final color = courseColor(s.course.colorSeed, theme.brightness);
              return Opacity(
                opacity: done ? 0.42 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${s.session.startSection}-${s.session.endSection}',
                          style: theme.textTheme.labelSmall?.copyWith(color: color),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          s.course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.session.room ?? '',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 最近一场考试的倒计时。
class _ExamLine extends StatelessWidget {
  const _ExamLine();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final nearest = nearestExam(state.exams, DateTime.now());
    if (nearest == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.event_note, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${nearest.exam.name} · ${nearest.started ? '已开始' : '还有 ${nearest.remainingText}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}




