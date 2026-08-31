import 'agenda.dart';
import 'models/timetable.dart';
import 'week_math.dart';

/// 同一天内一组互相交叠的实际课程。
///
/// 冲突按连通的时间段合并：三门课首尾交叠时只显示为一处，避免把同一问题
/// 拆成多条两两组合。停课、调课、补课和校历停课已经由日程层提前应用。
class ScheduleConflict {
  const ScheduleConflict({
    required this.date,
    required this.week,
    required this.sessions,
  });

  final DateTime date;
  final int week;
  final List<ResolvedSession> sessions;

  int get startMinutes => sessions
      .map((item) => item.startMinutes)
      .reduce((left, right) => left < right ? left : right);

  int get endMinutes => sessions
      .map((item) => item.endMinutes)
      .reduce((left, right) => left > right ? left : right);

  bool involvesSession(String sessionId) =>
      sessions.any((item) => item.session.id == sessionId);
}

/// 扫描整个学期，返回按日期和时间排序的实际课程冲突。
List<ScheduleConflict> detectScheduleConflicts(Timetable timetable) {
  final result = <ScheduleConflict>[];
  final dayCount = timetable.totalWeeks * 7;
  for (var offset = 0; offset < dayCount; offset++) {
    final date = timetable.termStart.add(Duration(days: offset));
    result.addAll(scheduleConflictsOnDate(timetable, date));
  }
  return result;
}

/// 检测指定日期的实际课程冲突；学期外日期返回空列表。
List<ScheduleConflict> scheduleConflictsOnDate(
  Timetable timetable,
  DateTime date,
) {
  final weekDay = weekDayOfDate(
    timetable.termStart,
    date,
    timetable.totalWeeks,
  );
  if (weekDay == null) return const [];

  final sessions = [...sessionsOnDate(timetable, date)]
    ..sort((left, right) {
      final start = left.startMinutes.compareTo(right.startMinutes);
      if (start != 0) return start;
      return left.endMinutes.compareTo(right.endMinutes);
    });
  if (sessions.length < 2) return const [];

  final result = <ScheduleConflict>[];
  var group = <ResolvedSession>[sessions.first];
  var groupEnd = sessions.first.endMinutes;

  void finishGroup() {
    if (group.length > 1) {
      result.add(
        ScheduleConflict(
          date: dateOnly(date),
          week: weekDay.week,
          sessions: List.unmodifiable(group),
        ),
      );
    }
  }

  for (final session in sessions.skip(1)) {
    if (session.startMinutes < groupEnd) {
      group.add(session);
      if (session.endMinutes > groupEnd) groupEnd = session.endMinutes;
      continue;
    }
    finishGroup();
    group = [session];
    groupEnd = session.endMinutes;
  }
  finishGroup();
  return result;
}
