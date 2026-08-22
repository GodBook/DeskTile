import 'models/course.dart';
import 'models/time_slot.dart';
import 'models/timetable.dart';
import 'week_math.dart';

/// 一个上课时段 + 它对应的课程 + 起止节次的时间，界面和提醒都直接用这个。
class ResolvedSession {
  const ResolvedSession({
    required this.session,
    required this.course,
    required this.startSlot,
    required this.endSlot,
  });

  final CourseSession session;
  final Course course;
  final TimeSlot startSlot;
  final TimeSlot endSlot;

  int get startMinutes => startSlot.startMinutes;
  int get endMinutes => endSlot.endMinutes;

  String get sectionText => session.startSection == session.endSection
      ? '第${session.startSection}节'
      : '第${session.startSection}-${session.endSection}节';

  String get timeText => '${startSlot.startText}-${endSlot.endText}';

  DateTime startOn(DateTime date) =>
      dateOnly(date).add(Duration(minutes: startMinutes));

  DateTime endOn(DateTime date) =>
      dateOnly(date).add(Duration(minutes: endMinutes));
}

/// 带日期的上课时段。
typedef DatedSession = ({DateTime date, ResolvedSession session});

/// 把 [CourseSession] 补全成 [ResolvedSession]；课程或节次时间缺失时返回 null。
ResolvedSession? resolve(Timetable t, CourseSession s) {
  final course = t.courseById(s.courseId);
  final startSlot = t.slotAt(s.startSection);
  final endSlot = t.slotAt(s.endSection);
  if (course == null || startSlot == null || endSlot == null) return null;
  return ResolvedSession(
    session: s,
    course: course,
    startSlot: startSlot,
    endSlot: endSlot,
  );
}

/// 第 [week] 周、星期 [day] 的课，按节次升序。
List<ResolvedSession> sessionsOnWeekDay(Timetable t, int week, int day) {
  final result = <ResolvedSession>[];
  for (final s in t.sessions) {
    if (s.day != day || !s.activeInWeek(week)) continue;
    final r = resolve(t, s);
    if (r != null) result.add(r);
  }
  result.sort((a, b) => a.session.startSection.compareTo(b.session.startSection));
  return result;
}

/// 某个日期的课；日期不在学期范围内则为空。
List<DatedSession> agendaForDate(Timetable t, DateTime date) {
  final wd = weekDayOfDate(t.termStart, date, t.totalWeeks);
  if (wd == null) return const [];
  return sessionsOnWeekDay(t, wd.week, wd.day)
      .map((s) => (date: dateOnly(date), session: s))
      .toList();
}

/// 从 [now] 起还没结束的课，按时间升序。跨天向后找，最多 [lookAheadDays] 天。
List<DatedSession> upcomingSessions(
  Timetable t,
  DateTime now, {
  int lookAheadDays = 14,
  int limit = 0,
}) {
  final result = <DatedSession>[];
  for (var offset = 0; offset <= lookAheadDays; offset++) {
    final date = dateOnly(now).add(Duration(days: offset));
    for (final item in agendaForDate(t, date)) {
      if (item.session.endOn(item.date).isAfter(now)) {
        result.add(item);
        if (limit > 0 && result.length >= limit) return result;
      }
    }
  }
  return result;
}

/// 当前正在上的课（开始了但还没结束）。
DatedSession? currentSession(Timetable t, DateTime now) {
  final list = upcomingSessions(t, now, lookAheadDays: 0, limit: 1);
  if (list.isEmpty) return null;
  final first = list.first;
  return first.session.startOn(first.date).isAfter(now) ? null : first;
}

/// 下一节还没开始的课。
DatedSession? nextSession(Timetable t, DateTime now, {int lookAheadDays = 14}) {
  for (final item in upcomingSessions(t, now, lookAheadDays: lookAheadDays)) {
    if (item.session.startOn(item.date).isAfter(now)) return item;
  }
  return null;
}

/// 今天剩下的课（含正在上的那节）。
List<DatedSession> remainingToday(Timetable t, DateTime now) =>
    upcomingSessions(t, now, lookAheadDays: 0);
