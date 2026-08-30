import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../academic_calendar.dart';
import '../agenda.dart';
import '../models/timetable.dart';

class IcsExport {
  const IcsExport({required this.calendar, required this.eventCount});

  final String calendar;
  final int eventCount;
}

/// 将整个学期的实际课程逐次展开为 iCalendar 事件。
///
/// 使用浮动本地时间，导入目标日历后会保留课表里的墙上时间。单次停课、调课、
/// 补课和校历批量停课均先由日程解析层处理，避免目标日历不支持复杂重复例外。
IcsExport exportIcs(Timetable timetable, {DateTime? generatedAt}) {
  final events = <({DateTime date, ResolvedSession session})>[];
  final lastDate = timetableEndDate(timetable);
  for (
    var date = timetable.termStart;
    !date.isAfter(lastDate);
    date = date.add(const Duration(days: 1))
  ) {
    events.addAll(agendaForDate(timetable, date));
  }
  if (events.isEmpty) {
    throw const FormatException('课表在本学期内没有实际课程，没什么可导出的');
  }

  final stamp = _utcDateTime(generatedAt ?? DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//DeskTile//Course Calendar//ZH-CN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escapeText(timetable.name)}',
    'X-WR-CALDESC:${_escapeText('由 DeskTile 课表岛导出的实际课程安排')}',
  ];

  for (final event in events) {
    final session = event.session;
    final description = <String>[
      if (_notEmpty(session.course.teacher))
        '教师：${session.course.teacher!.trim()}',
      '节次：${session.sectionText}',
      if (session.occurrence == SessionOccurrenceKind.rescheduledTarget)
        '安排：临时调课',
      if (session.occurrence == SessionOccurrenceKind.extraClass) '安排：临时补课',
      if (_notEmpty(session.course.note)) session.course.note!.trim(),
    ];
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${_eventUid(timetable, event.date, session)}',
      'DTSTAMP:$stamp',
      'DTSTART:${_localDateTime(session.startOn(event.date))}',
      'DTEND:${_localDateTime(session.endOn(event.date))}',
      'SUMMARY:${_escapeText(session.course.name)}',
      if (_notEmpty(session.session.room))
        'LOCATION:${_escapeText(session.session.room!.trim())}',
      'DESCRIPTION:${_escapeText(description.join('\n'))}',
      'CATEGORIES:${_escapeText('课程')},DeskTile',
      'STATUS:CONFIRMED',
      'TRANSP:OPAQUE',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');

  final calendar = '${lines.expand(_foldContentLine).join('\r\n')}\r\n';
  return IcsExport(calendar: calendar, eventCount: events.length);
}

String _eventUid(Timetable timetable, DateTime date, ResolvedSession session) {
  final identity = [
    timetable.id,
    session.session.id,
    _date(date),
    '${session.startMinutes}',
    '${session.endMinutes}',
  ].join('|');
  final digest = sha256.convert(utf8.encode(identity)).toString();
  return '${digest.substring(0, 32)}@desktile.local';
}

String _escapeText(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,');

Iterable<String> _foldContentLine(String line) sync* {
  var buffer = StringBuffer();
  var byteCount = 0;
  var limit = 75;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (byteCount > 0 && byteCount + length > limit) {
      yield buffer.toString();
      buffer = StringBuffer(' ');
      byteCount = 1;
      limit = 75;
    }
    buffer.write(character);
    byteCount += length;
  }
  yield buffer.toString();
}

String _localDateTime(DateTime value) =>
    '${_date(value)}T${_two(value.hour)}${_two(value.minute)}${_two(value.second)}';

String _utcDateTime(DateTime value) {
  final utc = value.toUtc();
  return '${_date(utc)}T${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}${_two(value.month)}${_two(value.day)}';

String _two(int value) => value.toString().padLeft(2, '0');

bool _notEmpty(String? value) => value != null && value.trim().isNotEmpty;
