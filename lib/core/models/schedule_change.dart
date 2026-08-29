import '../week_math.dart';

/// 单次课程变更，不改动原有的重复上课时段。
enum ScheduleChangeType { cancellation, reschedule, extraClass }

class ScheduleChange {
  ScheduleChange._({
    required this.id,
    required this.type,
    this.originalSessionId,
    DateTime? originalDate,
    this.courseId,
    DateTime? targetDate,
    this.startSection,
    this.endSection,
    this.room,
  }) : originalDate = originalDate == null ? null : dateOnly(originalDate),
       targetDate = targetDate == null ? null : dateOnly(targetDate);

  factory ScheduleChange.cancellation({
    required String id,
    required String originalSessionId,
    required DateTime originalDate,
  }) => ScheduleChange._(
    id: id,
    type: ScheduleChangeType.cancellation,
    originalSessionId: originalSessionId,
    originalDate: originalDate,
  );

  factory ScheduleChange.reschedule({
    required String id,
    required String originalSessionId,
    required DateTime originalDate,
    required DateTime targetDate,
    required int startSection,
    required int endSection,
    String? room,
  }) => ScheduleChange._(
    id: id,
    type: ScheduleChangeType.reschedule,
    originalSessionId: originalSessionId,
    originalDate: originalDate,
    targetDate: targetDate,
    startSection: startSection,
    endSection: endSection,
    room: room,
  );

  factory ScheduleChange.extraClass({
    required String id,
    required String courseId,
    required DateTime targetDate,
    required int startSection,
    required int endSection,
    String? room,
  }) => ScheduleChange._(
    id: id,
    type: ScheduleChangeType.extraClass,
    courseId: courseId,
    targetDate: targetDate,
    startSection: startSection,
    endSection: endSection,
    room: room,
  );

  final String id;
  final ScheduleChangeType type;

  /// 停课或调课对应的常规时段与原上课日期。
  final String? originalSessionId;
  final DateTime? originalDate;

  /// 补课对应的课程；调课课程由 [originalSessionId] 指向的时段取得。
  final String? courseId;

  /// 调课后的日期或补课日期，以及新的节次和教室。
  final DateTime? targetDate;
  final int? startSection;
  final int? endSection;
  final String? room;

  bool sourceMatches(String sessionId, DateTime date) =>
      type != ScheduleChangeType.extraClass &&
      originalSessionId == sessionId &&
      _sameDate(originalDate, date);

  bool targets(DateTime date) =>
      type != ScheduleChangeType.cancellation && _sameDate(targetDate, date);

  ScheduleChange shiftedByDays(int days) {
    if (days == 0) return this;
    DateTime shifted(DateTime date) =>
        DateTime(date.year, date.month, date.day + days);
    return switch (type) {
      ScheduleChangeType.cancellation => ScheduleChange.cancellation(
        id: id,
        originalSessionId: originalSessionId!,
        originalDate: shifted(originalDate!),
      ),
      ScheduleChangeType.reschedule => ScheduleChange.reschedule(
        id: id,
        originalSessionId: originalSessionId!,
        originalDate: shifted(originalDate!),
        targetDate: shifted(targetDate!),
        startSection: startSection!,
        endSection: endSection!,
        room: room,
      ),
      ScheduleChangeType.extraClass => ScheduleChange.extraClass(
        id: id,
        courseId: courseId!,
        targetDate: shifted(targetDate!),
        startSection: startSection!,
        endSection: endSection!,
        room: room,
      ),
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': switch (type) {
      ScheduleChangeType.cancellation => 'cancellation',
      ScheduleChangeType.reschedule => 'reschedule',
      ScheduleChangeType.extraClass => 'extraClass',
    },
    if (originalSessionId != null) 'originalSessionId': originalSessionId,
    if (originalDate != null) 'originalDate': _dateText(originalDate!),
    if (courseId != null) 'courseId': courseId,
    if (targetDate != null) 'targetDate': _dateText(targetDate!),
    if (startSection != null) 'startSection': startSection,
    if (endSection != null) 'endSection': endSection,
    if (room != null) 'room': room,
  };

  factory ScheduleChange.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final type = json['type'] as String?;
    return switch (type) {
      'cancellation' => ScheduleChange.cancellation(
        id: id,
        originalSessionId: json['originalSessionId'] as String,
        originalDate: DateTime.parse(json['originalDate'] as String),
      ),
      'reschedule' => ScheduleChange.reschedule(
        id: id,
        originalSessionId: json['originalSessionId'] as String,
        originalDate: DateTime.parse(json['originalDate'] as String),
        targetDate: DateTime.parse(json['targetDate'] as String),
        startSection: json['startSection'] as int,
        endSection: json['endSection'] as int,
        room: json['room'] as String?,
      ),
      'extraClass' => ScheduleChange.extraClass(
        id: id,
        courseId: json['courseId'] as String,
        targetDate: DateTime.parse(json['targetDate'] as String),
        startSection: json['startSection'] as int,
        endSection: json['endSection'] as int,
        room: json['room'] as String?,
      ),
      _ => throw const FormatException('无法识别的临时课程变更类型'),
    };
  }
}

bool _sameDate(DateTime? left, DateTime right) =>
    left != null &&
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
