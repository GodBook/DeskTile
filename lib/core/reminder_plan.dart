import 'agenda.dart';
import 'models/settings.dart';
import 'models/timetable.dart';
import 'stable_hash.dart';
import 'week_math.dart';

/// 一条待调度的提醒。id 由日期 + 时段 id 决定性生成，
/// 这样重排时先 cancelAll 再全量写入不会产生重复通知。
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime fireAt;
  final String title;
  final String body;

  @override
  String toString() => '[$id] $fireAt $title / $body';
}

/// 生成 [from] 起 [daysAhead] 天内的提醒计划。
///
/// - [ReminderMode.firstClassOfDay]：每天只提醒第一节课，且要求它开始得比
///   `settings.earlyClassCutoffMinutes` 早 —— 这就是「早八提醒」。
///   把阈值调到 24:00 就等于「每天第一节课都提醒」。
/// - [ReminderMode.everyClass]：每节课都提醒。
List<PlannedReminder> buildReminders({
  required Timetable timetable,
  required AppSettings settings,
  required DateTime from,
  int daysAhead = 7,
}) {
  if (!settings.reminderEnabled) return const [];

  final result = <PlannedReminder>[];
  for (var offset = 0; offset < daysAhead; offset++) {
    final date = dateOnly(from).add(Duration(days: offset));
    final agenda = agendaForDate(timetable, date);
    if (agenda.isEmpty) continue;

    final Iterable<DatedSession> targets;
    if (settings.reminderMode == ReminderMode.firstClassOfDay) {
      final first = agenda.first;
      targets = first.session.startMinutes < settings.earlyClassCutoffMinutes
          ? [first]
          : const [];
    } else {
      targets = agenda;
    }

    for (final item in targets) {
      final fireAt = item.session
          .startOn(item.date)
          .subtract(Duration(minutes: settings.leadMinutes));
      if (!fireAt.isAfter(from)) continue;
      result.add(
        PlannedReminder(
          id: reminderId(item.date, item.session.session.id),
          fireAt: fireAt,
          title: _title(settings.reminderMode, item),
          body: _body(item),
        ),
      );
    }
  }
  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return result;
}

String _title(ReminderMode mode, DatedSession item) {
  final name = item.session.course.name;
  return mode == ReminderMode.firstClassOfDay ? '早八提醒：$name' : '下节课：$name';
}

/// 正文一定带教室 —— 「早八不知道在哪间教室」是这个功能存在的理由。
String _body(DatedSession item) {
  final s = item.session;
  final parts = <String>['${s.startSlot.startText} 上课', s.sectionText];
  final room = s.session.room;
  if (room != null && room.trim().isNotEmpty) parts.add(room.trim());
  final teacher = s.course.teacher;
  if (teacher != null && teacher.trim().isNotEmpty) parts.add(teacher.trim());
  return parts.join(' · ');
}

/// 决定性通知 id（限制在 31 位内，Android 要求 32 位 int）。
int reminderId(DateTime date, String sessionId) =>
    stableHash('${date.year}-${date.month}-${date.day}|$sessionId') &
    0x3fffffff;
