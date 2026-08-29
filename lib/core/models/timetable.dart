import '../week_math.dart';
import 'course.dart';
import 'schedule_change.dart';
import 'time_slot.dart';

/// 一张完整的课表：学期信息 + 作息 + 课程 + 上课时段。
///
/// 课程和时段都挂在课表里，这样导入/导出/备份都是自包含的一份数据。
class Timetable {
  Timetable({
    required this.id,
    required this.name,
    required DateTime termStart,
    this.totalWeeks = 20,
    this.timeSlots = kDefaultTimeSlots,
    this.showWeekend = true,
    this.courses = const [],
    this.sessions = const [],
    this.scheduleChanges = const [],
  }) : termStart = mondayOf(termStart);

  final String id;
  final String name;

  /// 第一周的周一（构造时自动对齐到周一）。
  final DateTime termStart;
  final int totalWeeks;
  final List<TimeSlot> timeSlots;
  final bool showWeekend;
  final List<Course> courses;
  final List<CourseSession> sessions;
  final List<ScheduleChange> scheduleChanges;

  Course? courseById(String id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  CourseSession? sessionById(String id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  TimeSlot? slotAt(int section) {
    for (final s in timeSlots) {
      if (s.index == section) return s;
    }
    return null;
  }

  int get maxSection => timeSlots.isEmpty
      ? 0
      : timeSlots.map((s) => s.index).reduce((a, b) => a > b ? a : b);

  Timetable copyWith({
    String? name,
    DateTime? termStart,
    int? totalWeeks,
    List<TimeSlot>? timeSlots,
    bool? showWeekend,
    List<Course>? courses,
    List<CourseSession>? sessions,
    List<ScheduleChange>? scheduleChanges,
  }) => Timetable(
    id: id,
    name: name ?? this.name,
    termStart: termStart ?? this.termStart,
    totalWeeks: totalWeeks ?? this.totalWeeks,
    timeSlots: timeSlots ?? this.timeSlots,
    showWeekend: showWeekend ?? this.showWeekend,
    courses: courses ?? this.courses,
    sessions: sessions ?? this.sessions,
    scheduleChanges: scheduleChanges ?? this.scheduleChanges,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'termStart': _dateText(termStart),
    'totalWeeks': totalWeeks,
    'timeSlots': timeSlots.map((s) => s.toJson()).toList(),
    'showWeekend': showWeekend,
    'courses': courses.map((c) => c.toJson()).toList(),
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'scheduleChanges': scheduleChanges.map((c) => c.toJson()).toList(),
  };

  factory Timetable.fromJson(Map<String, dynamic> json) => Timetable(
    id: json['id'] as String,
    name: json['name'] as String,
    termStart: DateTime.parse(json['termStart'] as String),
    totalWeeks: (json['totalWeeks'] as int?) ?? 20,
    timeSlots:
        (json['timeSlots'] as List?)
            ?.map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
            .toList() ??
        kDefaultTimeSlots,
    showWeekend: (json['showWeekend'] as bool?) ?? true,
    courses: (json['courses'] as List? ?? [])
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList(),
    sessions: (json['sessions'] as List? ?? [])
        .map((e) => CourseSession.fromJson(e as Map<String, dynamic>))
        .toList(),
    scheduleChanges: (json['scheduleChanges'] as List? ?? [])
        .map((e) => ScheduleChange.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

String _dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
