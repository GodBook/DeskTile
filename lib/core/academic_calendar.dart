import 'models/academic_calendar_event.dart';
import 'models/timetable.dart';
import 'week_math.dart';

DateTime timetableEndDate(Timetable timetable) =>
    timetable.termStart.add(Duration(days: timetable.totalWeeks * 7 - 1));

List<AcademicCalendarEvent> calendarEventsOnDate(
  Timetable timetable,
  DateTime date,
) {
  final result = timetable.academicCalendarEvents
      .where((event) => event.contains(date))
      .toList();
  result.sort(_compareEvents);
  return result;
}

AcademicCalendarEvent? classSuspensionOnDate(
  Timetable timetable,
  DateTime date,
) {
  for (final event in calendarEventsOnDate(timetable, date)) {
    if (event.suspendsClasses) return event;
  }
  return null;
}

/// 校历事件会暂停的常规课程次数；已被单次停课或调出的课程不重复计数。
int affectedRegularSessionCount(
  Timetable timetable,
  AcademicCalendarEvent event,
) {
  if (!event.suspendsClasses) return 0;
  final first = event.startDate.isBefore(timetable.termStart)
      ? timetable.termStart
      : event.startDate;
  final termEnd = timetableEndDate(timetable);
  final last = event.endDate.isAfter(termEnd) ? termEnd : event.endDate;
  if (last.isBefore(first)) return 0;

  var count = 0;
  for (
    var date = first;
    !date.isAfter(last);
    date = date.add(const Duration(days: 1))
  ) {
    final weekDay = weekDayOfDate(
      timetable.termStart,
      date,
      timetable.totalWeeks,
    );
    if (weekDay == null) continue;
    for (final session in timetable.sessions) {
      if (session.day != weekDay.day || !session.activeInWeek(weekDay.week)) {
        continue;
      }
      final alreadyChanged = timetable.scheduleChanges.any(
        (change) => change.sourceMatches(session.id, date),
      );
      if (!alreadyChanged) count++;
    }
  }
  return count;
}

int suspendedCalendarDayCount(Timetable timetable) {
  final days = <String>{};
  final termEnd = timetableEndDate(timetable);
  for (final event in timetable.academicCalendarEvents) {
    if (!event.suspendsClasses) continue;
    final first = event.startDate.isBefore(timetable.termStart)
        ? timetable.termStart
        : event.startDate;
    final last = event.endDate.isAfter(termEnd) ? termEnd : event.endDate;
    for (
      var date = first;
      !date.isAfter(last);
      date = date.add(const Duration(days: 1))
    ) {
      days.add('${date.year}-${date.month}-${date.day}');
    }
  }
  return days.length;
}

int suspendedRegularSessionCount(Timetable timetable) {
  var count = 0;
  final termEnd = timetableEndDate(timetable);
  for (
    var date = timetable.termStart;
    !date.isAfter(termEnd);
    date = date.add(const Duration(days: 1))
  ) {
    if (classSuspensionOnDate(timetable, date) == null) continue;
    final event = AcademicCalendarEvent(
      id: 'summary',
      title: 'summary',
      type: AcademicCalendarEventType.other,
      startDate: date,
      endDate: date,
    );
    count += affectedRegularSessionCount(timetable, event);
  }
  return count;
}

int _compareEvents(AcademicCalendarEvent left, AcademicCalendarEvent right) {
  final date = left.startDate.compareTo(right.startDate);
  if (date != 0) return date;
  final end = left.endDate.compareTo(right.endDate);
  if (end != 0) return end;
  return left.id.compareTo(right.id);
}
