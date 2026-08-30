import 'academic_calendar.dart';
import 'models/academic_calendar_event.dart';
import 'models/course.dart';
import 'models/schedule_change.dart';
import 'models/time_slot.dart';
import 'models/timetable.dart';
import 'week_math.dart';

enum SessionOccurrenceKind {
  regular,
  cancelled,
  rescheduledSource,
  rescheduledTarget,
  extraClass,
  calendarSuspended,
}

/// 一个上课时段 + 它对应的课程 + 起止节次的时间，界面和提醒都直接用这个。
class ResolvedSession {
  const ResolvedSession({
    required this.session,
    required this.course,
    required this.startSlot,
    required this.endSlot,
    this.occurrence = SessionOccurrenceKind.regular,
    this.change,
    this.calendarEvent,
  });

  final CourseSession session;
  final Course course;
  final TimeSlot startSlot;
  final TimeSlot endSlot;
  final SessionOccurrenceKind occurrence;
  final ScheduleChange? change;
  final AcademicCalendarEvent? calendarEvent;

  bool get isInactive =>
      occurrence == SessionOccurrenceKind.cancelled ||
      occurrence == SessionOccurrenceKind.rescheduledSource ||
      occurrence == SessionOccurrenceKind.calendarSuspended;

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
ResolvedSession? resolve(
  Timetable t,
  CourseSession s, {
  SessionOccurrenceKind occurrence = SessionOccurrenceKind.regular,
  ScheduleChange? change,
  AcademicCalendarEvent? calendarEvent,
}) {
  final course = t.courseById(s.courseId);
  final startSlot = t.slotAt(s.startSection);
  final endSlot = t.slotAt(s.endSection);
  if (course == null || startSlot == null || endSlot == null) return null;
  return ResolvedSession(
    session: s,
    course: course,
    startSlot: startSlot,
    endSlot: endSlot,
    occurrence: occurrence,
    change: change,
    calendarEvent: calendarEvent,
  );
}

/// 第 [week] 周、星期 [day] 的课，按节次升序。
List<ResolvedSession> sessionsOnWeekDay(
  Timetable t,
  int week,
  int day, {
  bool includeChangedSources = false,
}) => sessionsOnDate(
  t,
  dateOfWeekDay(t.termStart, week, day),
  includeChangedSources: includeChangedSources,
);

/// 某个日期的实际课程；周视图可通过 [includeChangedSources] 同时显示已停课/调出的来源。
List<ResolvedSession> sessionsOnDate(
  Timetable t,
  DateTime date, {
  bool includeChangedSources = false,
}) {
  final weekDay = weekDayOfDate(t.termStart, date, t.totalWeeks);
  if (weekDay == null) return const [];
  final result = <ResolvedSession>[];
  final calendarSuspension = classSuspensionOnDate(t, date);
  for (final s in t.sessions) {
    if (s.day != weekDay.day || !s.activeInWeek(weekDay.week)) continue;
    ScheduleChange? sourceChange;
    for (final change in t.scheduleChanges) {
      if (change.sourceMatches(s.id, date)) {
        sourceChange = change;
        break;
      }
    }
    if (sourceChange != null) {
      if (includeChangedSources) {
        final occurrence = sourceChange.type == ScheduleChangeType.cancellation
            ? SessionOccurrenceKind.cancelled
            : SessionOccurrenceKind.rescheduledSource;
        final resolved = resolve(
          t,
          s,
          occurrence: occurrence,
          change: sourceChange,
        );
        if (resolved != null) result.add(resolved);
      }
      continue;
    }
    if (calendarSuspension != null) {
      if (includeChangedSources) {
        final resolved = resolve(
          t,
          s,
          occurrence: SessionOccurrenceKind.calendarSuspended,
          calendarEvent: calendarSuspension,
        );
        if (resolved != null) result.add(resolved);
      }
      continue;
    }
    final r = resolve(t, s);
    if (r != null) result.add(r);
  }

  for (final change in t.scheduleChanges) {
    if (!change.targets(date)) continue;
    final courseId = switch (change.type) {
      ScheduleChangeType.reschedule =>
        t.sessionById(change.originalSessionId ?? '')?.courseId,
      ScheduleChangeType.extraClass => change.courseId,
      ScheduleChangeType.cancellation => null,
    };
    final start = change.startSection;
    final end = change.endSection;
    if (courseId == null || start == null || end == null) continue;
    final session = CourseSession(
      id: 'change:${change.id}',
      courseId: courseId,
      day: weekDay.day,
      startSection: start,
      endSection: end,
      weeks: {weekDay.week},
      room: change.room,
    );
    final occurrence = change.type == ScheduleChangeType.reschedule
        ? SessionOccurrenceKind.rescheduledTarget
        : SessionOccurrenceKind.extraClass;
    final resolved = resolve(
      t,
      session,
      occurrence: occurrence,
      change: change,
    );
    if (resolved != null) result.add(resolved);
  }

  result.sort((a, b) {
    final section = a.session.startSection.compareTo(b.session.startSection);
    if (section != 0) return section;
    if (a.isInactive == b.isInactive) return 0;
    return a.isInactive ? -1 : 1;
  });
  return result;
}

/// 某个日期的课；日期不在学期范围内则为空。
List<DatedSession> agendaForDate(Timetable t, DateTime date) {
  final wd = weekDayOfDate(t.termStart, date, t.totalWeeks);
  if (wd == null) return const [];
  return sessionsOnDate(
    t,
    date,
  ).map((s) => (date: dateOnly(date), session: s)).toList();
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
