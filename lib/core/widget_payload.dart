import 'dart:convert';

import 'agenda.dart';
import 'exam_countdown.dart';
import 'models/exam.dart';
import 'models/timetable.dart';
import 'week_math.dart';

/// Shared-storage key used by the Android Glance widget.
///
/// Keep this value stable: changing it leaves already-installed widgets with
/// their previous value until the app writes the new key.
const androidWidgetPayloadKey = 'desktile_widget_payload';

/// Fully-qualified receiver name consumed by [HomeWidget.updateWidget].
const androidWidgetProviderName =
    'com.desktile.desktile.widget.DeskTileWidgetReceiver';

/// Compact, platform-neutral snapshot rendered by the Android home-screen
/// widget.
///
/// The class intentionally contains only strings, integers and a JSON
/// encoder. It can therefore be unit-tested without Flutter bindings and can
/// be written through `HomeWidget.saveWidgetData<String>` on Android.
class WidgetPayload {
  const WidgetPayload({
    required this.week,
    required this.weekday,
    required this.weekdayLabel,
    required this.nextTitle,
    required this.nextRoom,
    required this.nextTime,
    required this.nextDayLabel,
    required this.nextIsCurrent,
    required this.remainingToday,
    required this.examTitle,
    required this.examAt,
    required this.examRoom,
    required this.examCountdown,
  });

  /// Current semester week, or 0 when the date is outside the semester.
  final int week;

  /// Current weekday (1 = Monday), or 0 when outside the semester.
  final int weekday;

  final String weekdayLabel;
  final String nextTitle;
  final String nextRoom;
  final String nextTime;
  final String nextDayLabel;
  final bool nextIsCurrent;
  final int remainingToday;
  final String examTitle;
  final String examAt;
  final String examRoom;
  final String examCountdown;

  /// A stable map representation for callers that prefer saving individual
  /// fields or inspecting the payload in tests.
  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'week': week,
    'weekday': weekday,
    'weekdayLabel': weekdayLabel,
    'nextTitle': nextTitle,
    'nextRoom': nextRoom,
    'nextTime': nextTime,
    'nextDayLabel': nextDayLabel,
    'nextIsCurrent': nextIsCurrent,
    'remainingToday': remainingToday,
    'examTitle': examTitle,
    'examAt': examAt,
    'examRoom': examRoom,
    'examCountdown': examCountdown,
  };

  /// JSON string written to HomeWidget's shared preferences.
  String encode() => jsonEncode(toMap());

  /// Alias useful at call sites that use JSON terminology.
  String toJson() => encode();

  factory WidgetPayload.fromMap(Map<String, dynamic> map) => WidgetPayload(
    week: _intValue(map['week']),
    weekday: _intValue(map['weekday']),
    weekdayLabel: _stringValue(map['weekdayLabel']),
    nextTitle: _stringValue(map['nextTitle']),
    nextRoom: _stringValue(map['nextRoom']),
    nextTime: _stringValue(map['nextTime']),
    nextDayLabel: _stringValue(map['nextDayLabel']),
    nextIsCurrent: map['nextIsCurrent'] == true,
    remainingToday: _intValue(map['remainingToday']),
    examTitle: _stringValue(map['examTitle']),
    examAt: _stringValue(map['examAt']),
    examRoom: _stringValue(map['examRoom']),
    examCountdown: _stringValue(map['examCountdown']),
  );

  factory WidgetPayload.fromJson(String source) =>
      WidgetPayload.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// Build the snapshot from the same core agenda/exam functions used by the
/// desktop UI. Supplying [now] makes this deterministic in unit tests.
WidgetPayload buildWidgetPayload({
  required Timetable? timetable,
  List<Exam> exams = const [],
  DateTime? now,
}) {
  final instant = now ?? DateTime.now();
  final weekDay = timetable == null
      ? null
      : weekDayOfDate(timetable.termStart, instant, timetable.totalWeeks);

  final today = timetable == null
      ? const <DatedSession>[]
      : remainingToday(timetable, instant);
  final current = timetable == null ? null : currentSession(timetable, instant);
  final next =
      current ?? (timetable == null ? null : nextSession(timetable, instant));
  final nearest = nearestExam(exams, instant);

  return WidgetPayload(
    week: weekDay?.week ?? 0,
    weekday: weekDay?.day ?? 0,
    weekdayLabel: weekDay == null ? '学期外' : weekDayName(weekDay.day),
    nextTitle: next?.session.course.name ?? '',
    nextRoom: next?.session.session.room ?? '',
    nextTime: next?.session.timeText ?? '',
    nextDayLabel: next == null
        ? ''
        : next.date.year == instant.year &&
              next.date.month == instant.month &&
              next.date.day == instant.day
        ? '今天'
        : weekDayName(next.date.weekday),
    nextIsCurrent: current != null,
    remainingToday: today.length,
    examTitle: nearest?.exam.name ?? '',
    examAt: nearest == null ? '' : _dateTimeText(nearest.exam.startAt),
    examRoom: nearest?.exam.room ?? '',
    examCountdown: nearest?.remainingText ?? '',
  );
}

String _dateTimeText(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

int _intValue(Object? value) => value is num ? value.toInt() : 0;

String _stringValue(Object? value) => value is String ? value : '';
