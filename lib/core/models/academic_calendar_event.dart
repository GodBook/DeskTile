import '../week_math.dart';

enum AcademicCalendarEventType { holiday, examWeek, suspension, other }

/// 学期中的一段校历安排。它可以只做标记，也可以暂停范围内的常规课程。
class AcademicCalendarEvent {
  AcademicCalendarEvent({
    required this.id,
    required this.title,
    required this.type,
    required DateTime startDate,
    required DateTime endDate,
    this.suspendsClasses = true,
  }) : startDate = dateOnly(startDate),
       endDate = dateOnly(endDate) {
    if (this.endDate.isBefore(this.startDate)) {
      throw ArgumentError.value(endDate, 'endDate', '结束日期不能早于开始日期');
    }
  }

  final String id;
  final String title;
  final AcademicCalendarEventType type;
  final DateTime startDate;
  final DateTime endDate;
  final bool suspendsClasses;

  int get dayCount => endDate.difference(startDate).inDays + 1;

  bool contains(DateTime date) {
    final value = dateOnly(date);
    return !value.isBefore(startDate) && !value.isAfter(endDate);
  }

  AcademicCalendarEvent copyWith({
    String? title,
    AcademicCalendarEventType? type,
    DateTime? startDate,
    DateTime? endDate,
    bool? suspendsClasses,
  }) => AcademicCalendarEvent(
    id: id,
    title: title ?? this.title,
    type: type ?? this.type,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    suspendsClasses: suspendsClasses ?? this.suspendsClasses,
  );

  AcademicCalendarEvent shiftedByDays(int days) => days == 0
      ? this
      : AcademicCalendarEvent(
          id: id,
          title: title,
          type: type,
          startDate: startDate.add(Duration(days: days)),
          endDate: endDate.add(Duration(days: days)),
          suspendsClasses: suspendsClasses,
        );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type.name,
    'startDate': _dateText(startDate),
    'endDate': _dateText(endDate),
    'suspendsClasses': suspendsClasses,
  };

  factory AcademicCalendarEvent.fromJson(Map<String, dynamic> json) =>
      AcademicCalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        type: _typeByName(json['type']),
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        suspendsClasses: (json['suspendsClasses'] as bool?) ?? true,
      );
}

AcademicCalendarEventType _typeByName(Object? name) {
  for (final value in AcademicCalendarEventType.values) {
    if (value.name == name) return value;
  }
  return AcademicCalendarEventType.other;
}

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
